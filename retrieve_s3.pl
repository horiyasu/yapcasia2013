#!/usr/bin/env perl
use strict;

use AWS::CLIWrapper;
use Data::Dumper;

my $aws = AWS::CLIWrapper->new(
    region => 'ap-northeast-1',
);

my $res = $aws->s3( 'ls' => {} );

print Dumper($res);

