use strict;
use warnings;

use DateTime qw< >;
use DateTime::Event::Recurrence qw< >;
use DateTime::Span qw< >;

use Test::More tests => 1;


my $recurrence =
    DateTime::Event::Recurrence
        ->daily(hours => 16, minutes => 15)
        ->set_time_zone('America/Chicago');

# Daylight Savings change at 0800 UTC in America/Chicago.
my $start = DateTime->new(
    year        => 2011,
    month       => 3,
    day         => 13,
    hour        => 21,
    time_zone   => 'UTC',
);
my $end = $start->clone()->add(hours => 1);

my $intersecting_range =
    DateTime::Span->from_datetimes(start => $start, end => $end);

ok(
    $intersecting_range->intersects($recurrence),
    'Range of 2100 to 2200 2011/3/13 UTC intersects with daily recurrence of 1615 America/Chicago.'
);
