package probes::LDAP;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man probes::LDAP>

to view the documentation or the command

C<smokeping -makepod probes::LDAP>

to generate the POD document.

=cut

use strict;
use probes::passwordchecker;
use Net::LDAP;
use Time::HiRes qw(gettimeofday sleep);
use base qw(probes::passwordchecker);
use IO::Socket::SSL;

my $DEFAULTINTERVAL = 1;

sub pod_hash {
	return {
		name => <<DOC,
probes::LDAP - a LDAP probe for SmokePing
DOC
		overview => <<DOC,
Measures LDAP search latency for SmokePing
DOC
		description => <<DOC,
This probe measures LDAP query latency for SmokePing.
The query is specified by the target-specific variable `filter' and,
optionally, by the target-specific variable `base'. The attributes 
queried can be specified in the comma-separated list `attrs'.

The TCP port of the LDAP server and the LDAP version to be used can
be specified by the variables `port' and `version'.

The probe can issue the starttls command to convert the connection
into encrypted mode, if so instructed by the `start_tls' variable.
It can also optionally do an authenticated LDAP bind, if the `binddn'
variable is present. The password to be used can be specified by the
target-specific variable `password' or in an external file.
The location of this file is given in the probe-specific variable
`passwordfile'. See probes::passwordchecker(3pm) for the format
of this file (summary: colon-separated triplets of the form
`<host>:<bind-dn>:<password>')

The probe tries to be nice to the server and does not send authentication
requests more frequently than once every X seconds, where X is the value
of the target-specific "min_interval" variable ($DEFAULTINTERVAL by default).
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
		bugs => <<DOC,
There should be a way of specifying TLS options, such as the certificates
involved etc.

The probe has an ugly way of working around the fact that the 
IO::Socket::SSL class complains if start_tls() is done more than once
in the same program. But It Works For Me (tm).
DOC
	}
}

sub ProbeDesc {
	return "LDAP queries";
}

sub probevars {
	my $class = shift;
	my $h = $class->SUPER::probevars;
	delete $h->{timeout};
	return $h;
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		_mandatory => [ 'filter' ],
		port => {
			_re => '\d+',
			_doc => "TCP port of the LDAP server",
			_example => 389,
		},
		version => {
			_re => '\d+',
			_doc => "The LDAP version to be used.",
			_example => 3,
		},
		start_tls => {
			_doc => "If true, encrypt the connection with the starttls command. Disabled by default.",
			_example => "1",
		},
		timeout => {
			_doc => "LDAP query timeout in seconds.",
			_re => '\d+',
			_example => 10,
			_default => 5,
		},
		base => {
			_doc => "The base to be used in the LDAP query",
			_example => "dc=foo,dc=bar",
		},
		filter => {
			_doc => "The actual search to be made",
			_example => "uid=testuser",
		},
		attrs => {
			_doc => "The attributes queried.",
			_example => "uid,someotherattr",
		},
		binddn => {
			_doc => "If present, authenticate the LDAP bind with this DN.",
			_example => "uid=testuser,dc=foo,dc=bar",
		},
		password => {
			_doc => "The password to be used, if not present in <passwordfile>.",
			_example => "mypass",
		},
                mininterval => {
                        _default => $DEFAULTINTERVAL,
                        _doc => "The minimum interval between each query sent, in (possibly fractional) second
s.",
                        _re => '(\d*\.)?\d+',
                },
	});
}

sub new {
	my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self = $class->SUPER::new(@_);

	return $self;
}

sub pingone {
	my $self = shift;
	my $target = shift;
	my $host = $target->{addr};
	my $vars = $target->{vars};

	my $version = $vars->{version} || 3;
	my $port = $vars->{port};

	my $mininterval = $vars->{mininterval};

	my $binddn = $vars->{binddn};

	my $timeout = $vars->{timeout};

	my $password;
	if (defined $binddn) {
		$password = $self->password($host, $binddn);
		if (defined $vars->{password} and
		    $vars->{password} ne ($self->{properties}{password}||"")) {
			$password = $vars->{password};
		}
		$password ||= $self->{properties}{password};
	}

	my $start_tls = $vars->{start_tls};

	my $filter = $vars->{filter};

	my $base = $vars->{base};

	my $attrs = $vars->{attrs};

	my @attrs = split(/,/, $attrs||"");
	my $attrsref = @attrs ? \@attrs : undef;

	my @times;
	
	my $start;
	for (1..$self->pings($target)) {
		if (defined $start) {
			my $elapsed = gettimeofday() - $start;
			my $timeleft = $mininterval - $elapsed;
			sleep $timeleft if $timeleft > 0;
		}
		local $IO::Socket::SSL::SSL_Context_obj; # ugly but necessary
		$start = gettimeofday();
		my $ldap = new Net::LDAP($host, port => $port, version => $version, timeout => $timeout) 
			or do {
				$self->do_log("connection error on $host: $!");
				next;
			};
		my $mesg;
		if ($start_tls) {
			$mesg = $ldap->start_tls;
			$mesg->code and do {
				$self->do_log("start_tls error on $host: " . $mesg->error);
				$ldap->unbind;
				next;
			}
		}
		if (defined $binddn and defined $password) {
			$mesg = $ldap->bind($binddn, password => $password);
		} else {
			if (defined $binddn and not defined $password) {
				$self->do_debug("No password specified for $binddn, doing anonymous bind instead");
			}
			$mesg = $ldap->bind();
		}
		$mesg->code and do {
			$self->do_log("bind error on $host: " . $mesg->error);
			$ldap->unbind;
			next;
		};
		$mesg = $ldap->search(base => $base, filter => $filter, attrs => $attrsref);
		$mesg->code and do {
			$self->do_log("filter error on $host: " . $mesg->error);
			$ldap->unbind;
			next;
		};
		$ldap->unbind;
		my $end = gettimeofday();
		my $elapsed = $end - $start;

		$self->do_debug("$host: LDAP query $_ took $elapsed seconds");

		push @times, $elapsed;
	}
	return sort { $a <=> $b } @times;
}


1;