use strict;

use Test::More tests => 6;
use DateTime;
use DateTime::Event::Recurrence;

my $dt1;
my $dt2;

sub calc 
{
    my @dt = $_[0]->as_list( start => $dt1, end => $dt2 );
    my $r = join(' ', map { $_->datetime } @dt);
    return $r;
}


    $dt1 = new DateTime( year => 2003, month => 4, day => 28,
                           hour => 12, minute => 10, second => 45,
                           nanosecond => 123456,
                           time_zone => 'UTC' );

    $dt2 = new DateTime( year => 2006, month => 5, day => 01,
                           hour => 12, minute => 10, second => 45,
                           nanosecond => 123456,
                           time_zone => 'UTC' );

    my $yearly = yearly DateTime::Event::Recurrence(
           weeks => 1, week_start_day => 'mo' );
    is( calc( $yearly ), 
        '2003-12-29T00:00:00 2005-01-03T00:00:00 2006-01-02T00:00:00',
        "yearly-weekly mo" );

    $yearly = yearly DateTime::Event::Recurrence(
           weeks => 1, week_start_day => 'su' );
    is( calc( $yearly ),
        '2004-01-04T00:00:00 2005-01-02T00:00:00 2006-01-01T00:00:00',
        "yearly-weekly su" );

    $yearly = yearly DateTime::Event::Recurrence(
           weeks => 1, week_start_day => 'tu' );
    is( calc( $yearly ),
        '2003-12-30T00:00:00 2005-01-04T00:00:00 2006-01-03T00:00:00',
        "yearly-weekly tu" );

    $yearly = yearly DateTime::Event::Recurrence(
           weeks => 1, week_start_day => '1mo' );
    is( calc( $yearly ),
        '2004-01-05T00:00:00 2005-01-03T00:00:00 2006-01-02T00:00:00',
        "yearly-weekly 1mo" );

    $yearly = yearly DateTime::Event::Recurrence(
           weeks => 1, week_start_day => '1su' );
    is( calc( $yearly ),
        '2004-01-04T00:00:00 2005-01-02T00:00:00 2006-01-01T00:00:00',
        "yearly-weekly 1su" );

    $yearly = yearly DateTime::Event::Recurrence(
           weeks => 1, week_start_day => '1tu' );
    is( calc( $yearly ),
        '2004-01-06T00:00:00 2005-01-04T00:00:00 2006-01-03T00:00:00',
        "yearly-weekly 1tu" );

__END__

    # MONTHLY

    $dt2 = new DateTime( year => 2004, month => 5, day => 01,
                           hour => 12, minute => 10, second => 45,
                           nanosecond => 123456,
                           time_zone => 'UTC' );

    my $monthly = monthly DateTime::Event::Recurrence(
           weeks => 1, week_start_day => '1mo' );
    is( calc( $monthly ),
        '2003-12-29T00:00:00 2005-01-03T00:00:00 2006-01-02T00:00:00',
        "monthly-weekly 1mo" );

    $monthly = monthly DateTime::Event::Recurrence(
           weeks => 1, week_start_day => '1su' );
    is( calc( $monthly ),
        '2003-12-29T00:00:00 2005-01-03T00:00:00 2006-01-02T00:00:00',
        "monthly-weekly 1su" );

    $monthly = monthly DateTime::Event::Recurrence(
           weeks => 1, week_start_day => '1tu' );
    is( calc( $monthly ),
        '2003-12-29T00:00:00 2005-01-03T00:00:00 2006-01-02T00:00:00',
        "monthly-weekly 1tu" );



