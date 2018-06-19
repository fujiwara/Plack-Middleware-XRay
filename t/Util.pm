package t::Util;

use strict;
use warnings;
use AWS::XRay;
use Exporter 'import';
use Test::More;
use IO::Scalar;
use JSON::XS;

our @EXPORT_OK = qw/ reset segments /;

my $buf;
no warnings 'redefine';

*AWS::XRay::sock = sub {
    IO::Scalar->new(\$buf);
};

sub reset {
    undef $buf;
}

sub segments {
    return unless $buf;
    $buf =~ s/{"format":"json","version":1}//g;
    my @seg = split /\n/, $buf;
    shift @seg; # despose first ""
    return map { decode_json($_) } @seg;
}

1;