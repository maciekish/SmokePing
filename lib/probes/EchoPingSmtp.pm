package probes::EchoPingSmtp;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man probes::EchoPingSmtp>

to view the documentation or the command

C<smokeping -makepod probes::EchoPingSmtp>

to generate the POD document.

=cut

use strict;
use base qw(probes::EchoPing);
use Carp;

sub pod_hash {
	return {
		name => <<DOC,
probes::EchoPingSmtp - an echoping(1) probe for SmokePing
DOC
		overview => <<DOC,
Measures SMTP roundtrip times (mail servers) for SmokePing.
DOC
		notes => <<DOC,
The I<fill>, I<size> and I<udp> EchoPing variables are not valid.
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
		see_also => <<DOC,
EchoPing(3pm)
DOC
	}
}

sub _init {
	my $self = shift;
	# SMTP doesn't fit with filling or size
	my $arghashref = $self->features;
	delete $arghashref->{size};
	delete $arghashref->{fill};
}

sub proto_args {
	return ("-S");
}

sub test_usage {
	my $self = shift;
	my $bin = $self->{properties}{binary};
	croak("Your echoping binary doesn't support SMTP")
		if `$bin -S 127.0.0.1 2>&1` =~ /(not compiled|invalid option|usage)/i;
	$self->SUPER::test_usage;
	return;
}

sub ProbeDesc($) {
        return "SMTP pings using echoping(1)";
}

sub targetvars {
	my $class = shift;
	my $h = $class->SUPER::targetvars;
	delete $h->{udp};
	delete $h->{fill};
	delete $h->{size};
	return $h;
}

1;