use strict;
use warnings;
use ExtUtils::MakeMaker;

my %pm = map { $_ => "\$(INST_LIB)/$_" } map { "HTTP/Any/$_.pm "} qw(Curl AnyEvent LWP Util);
$pm{'HTTP/Any.pod'} = '$(INST_LIB)/HTTP/Any.pod';

WriteMakefile(
	NAME         => "HTTP::Any",
	ABSTRACT     => 'HTML::Any - a common interface for HTTP clients (LWP, AnyEvent::HTTP, Curl)',
	AUTHOR       => '<kni@cpan.org>',
	LICENSE      => "perl",
	VERSION      => "0.02",
	PM           => \%pm,
);
