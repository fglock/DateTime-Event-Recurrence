package DateTime::Event::ICal;

use strict;
require Exporter;
use Carp;
use DateTime;
use DateTime::Set;
use DateTime::Span;
use DateTime::Event::Recurrence;
use Params::Validate qw(:all);
use vars qw( $VERSION @ISA );
@ISA     = qw( Exporter );
$VERSION = '0.00_00';

use constant INFINITY     =>       100 ** 100 ** 100 ;
use constant NEG_INFINITY => -1 * (100 ** 100 ** 100);

sub recur {
    my $class = shift;
    # TODO - insert Params::Validate here!
    my %args = @_;

    # dtstart dtend until
    my $span = 
        exists $args{dtstart} ?
            DateTime::Span->from_datetimes( start => $args{dtstart} ) :
            DateTime::Set->empty_set->complement;
    $span = $span->complement( 
                DateTime::Span->from_datetimes( after => delete $args{dtend} )
            ) if exists $args{dtend};
    $span = $span->complement(
                DateTime::Span->from_datetimes( after => delete $args{until} )
            ) if exists $args{until};

    # setup the "default time"
    my $dtstart = exists $args{dtstart} ?
            delete $args{dtstart} : 
            DateTime->new( year => 2000, month => 1, day => 1 );

    my %by;
    # bysecond byminute byhour
    if ( $args{freq} ne 'secondly' ) {
        $by{seconds} = exists $args{bysecond} ? 
                       delete $args{bysecond} : $dtstart->second;
        if ( $args{freq} ne 'minutely' ) {
            $by{minutes} = exists $args{byminute} ? 
                           delete $args{byminute} : $dtstart->minute;
            if ( $args{freq} ne 'hourly' ) {
                $by{hours} = exists $args{byhour} ? 
                             delete $args{byhour} : $dtstart->hour;
            }
        }
    }

    # use DT::E::Recurrence directly, if possible
    if ( $args{freq} eq 'weekly' ) {
        $by{days} = exists $args{byday} ?
                    delete $args{byday} : $dtstart->day_of_week;
    }
    elsif ( $args{freq} eq 'monthly' ) {
        $by{days} = exists $args{bymonthday} ?
                    delete $args{bymonthday} : $dtstart->day;
    }
    elsif ( $args{freq} eq 'yearly' ) {
        $by{days} = exists $args{byyearday} ?
                    delete $args{byyearday} : $dtstart->day_of_year;
    }

    # freq
    no strict 'refs';
    my $base_set = &{"DateTime::Event::Recurrence::$args{freq}"} ( undef, %by );

    # TODO!

    # count

    # interval

    # wkst
    # bysetpos
    # byday
    # bymonthday byyearday
    # byweekno
    # bymonth

    # check for nonprocessed arguments
    delete $args{freq};
    my @args = %args;
    warn "remaining args are not implemented: @args" if @args;

    return $base_set;
}


=head1 NAME

DateTime::Event::ICal - Perl DateTime extension for computing rfc2445 recurrences.

=head1 SYNOPSIS

 use DateTime;
 use DateTime::Event::ICal;
 
 my $dt = DateTime->new( year   => 2000,
                         month  => 6,
                         day    => 20,
                       );

 my $set = DateTime::Event::ICal->recur( %args );

 my $dt_next = $set->next( $dt );

 my $dt_previous = $set->previous( $dt );

 my $bool = $set->contains( $dt );

 my @days = $set->as_list( start => $dt1, end => $dt2 );

 my $iter = $set->iterator;

 while ( my $dt = $iter->next ) {
     print ' ', $dt->datetime;
 }

=head1 DESCRIPTION

This module provides convenience methods that let you easily create
C<DateTime::Set> objects for rfc2445 style recurrences.

=head1 USAGE

=over 4

=item * recur

This method returns a C<DateTime::Set> object representing the
given recurrence.

  my $set = DateTime::Event::ICal->recur( %args );

=over 4

=item * dtstart

C<dtstart> is not included in the recurrence, unless it satisfy the rule.

=item * dtend

=item * freq

=item * until

=item * count

=item * interval

=item * wkst

=item * bysetpos

=item * bysecond byminute byhour

=item * byday 

=item * bymonthday byyearday

=item * byweekno

=item * bymonth

=back

=back

=head1 AUTHOR

Flavio Soibelmann Glock
fglock@pucrs.br

=head1 CREDITS

The API is under development, with help from the people
in the datetime@perl.org list. 

=head1 COPYRIGHT

Copyright (c) 2003 Flavio Soibelmann Glock.  
All rights reserved.  This program
is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

The full text of the license can be found in the LICENSE file included
with this module.

=head1 SEE ALSO

datetime@perl.org mailing list

DateTime Web page at http://datetime.perl.org/

DateTime

DateTime::Event::Recurrence

DateTime::Set 

DateTime::SpanSet 

=cut
1;

