#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

use Auto::Weibo;


my $wb = Auto::Weibo->new('18922041025', 'alabos111');

$wb->do_login();
