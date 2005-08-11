#!/usr/bin/perl -w

use strict;

use Test::More tests => 3;

use DateTime;
use DateTime::Event::Recurrence;

# This test was taken from a bug report by Simon Wistow 	

my $start =  DateTime->new( year => 2005, month => 8, day => 1, hour => 13 );
$start->set_time_zone('Europe/London');

my $recur = DateTime::Event::Recurrence->monthly( start => $start );

$recur->set_time_zone('Europe/London');

my $dt = DateTime->new( year => 2005, month => 7, day => 27 );

my @result = (
'2005-08-01 Europe/London', 
'2005-09-01 Europe/London', 
'2005-10-01 Europe/London' );


for my $x ( 0 .. 2 ) {
    $dt = $recur->next( $dt );
    is( $dt->ymd." ". $dt->time_zone->name, $result[$x] );
}


