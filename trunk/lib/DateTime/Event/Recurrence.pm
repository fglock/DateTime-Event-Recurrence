package DateTime::Event::Recurrence;

use strict;
require Exporter;
use Carp;
use DateTime;
use DateTime::Set;
use DateTime::Span;
use Params::Validate qw(:all);
use vars qw( $VERSION @ISA );
@ISA     = qw( Exporter );
$VERSION = '0.00_04';

# -------- CONSTRUCTORS

BEGIN {
    # setup constructors daily, monthly, ...
    my @freq = qw( 
        year   years   yearly
        month  months  monthly
        day    days    daily
        hour   hours   hourly
        minute minutes minutely
        second seconds secondly );
    while ( @freq ) 
    {
        my ( $name, $names, $namely ) = ( shift @freq, shift @freq, shift @freq );
        my $sub = "
            sub ".__PACKAGE__."::$namely {
                my \$class = shift;
                my \%args = \@_;
                my \$duration;   # closure
                if ( exists \$args{ duration } ) {
                    \$duration = delete \$args{ duration };
                    \$duration = \$duration->clone;  # make it immutable
                }
                \$duration = new DateTime::Duration( \%args ) if keys \%args;
                bless {
                   next => sub { 

                       my \$tmp = \$_[0]->clone;
                       \$tmp->truncate( to => '$name' );
                       if ( \$duration ) {
                           \$tmp->add( $names => 1 ) 
                               while ( \$tmp + \$duration ) <= \$_[0];
                           \$tmp->add_duration( \$duration );
                       }
                       else {
                           \$tmp->add( $names => 1 ) while \$tmp <= \$_[0];
                       }
                       return \$tmp;

                   },
                   previous => sub {

                       my \$tmp = \$_[0]->clone;
                       \$tmp->truncate( to => '$name' );
                       if ( \$duration ) {
                           \$tmp->subtract( $names => 1 )
                               while ( \$tmp + \$duration ) >= \$_[0];
                           \$tmp->add_duration( \$duration );
                       }
                       else {
                           \$tmp->subtract( $names => 1 ) while \$tmp >= \$_[0];
                       }
                       return \$tmp;

                   }
                }, \$class;
            } ";
        # warn $sub;
        eval $sub;
        warn $@ if $@;
    }
} # BEGIN


sub weekly {
    my $class = shift;
    my %args = @_;
    # day_of_week_0 = 0-6 (Monday is 0)
    my $duration;   # closure
    if ( exists $args{ duration } ) {
        $duration = delete $args{ duration };
        $duration = $duration->clone;  # make it immutable
    }
    $duration = new DateTime::Duration( %args ) if keys %args; 
    bless {
        next => sub { 
            # warn 'next '.$_[0];
            my $tmp = $_[0]->clone;
            $tmp->truncate( to => 'day' )
                ->subtract( days => $_[0]->day_of_week_0 );
            if ( $duration ) {
                $tmp->add( days => 7 )
                    while ( $tmp + $duration ) <= $_[0];
                $tmp->add_duration( $duration );
            }
            else {
                $tmp->add( days => 7 ) while $tmp <= $_[0];
            }
            return $tmp;
        },
        previous => sub {
            # warn 'previous '.$_[0];
            my $tmp = $_[0]->clone;
            $tmp->truncate( to => 'day' )
                 ->subtract( days => $_[0]->day_of_week_0 );
            if ( $duration ) {
                $tmp->subtract( days => 7 )
                    while ( $tmp + $duration ) >= $_[0];
                $tmp->add_duration( $duration );
            }
            else {
                $tmp->subtract( days => 7 ) while $tmp >= $_[0];
            }
            return $tmp;
        }
    }, $class;
}

# ------- ACCESSORS
# these are (or should be) inheritable by other DateTime::Event::xxx classes

sub as_set {
    my $self = shift;
    unless ( exists $self->{set} ) 
    {
        $self->{set} = DateTime::Set->from_recurrence( 
                           recurrence => $self->{next} );
    }
    return $self->{set};
}

sub as_list {
    my $self = shift;
    my $span = DateTime::Span->new ( @_ );
    $self->as_set->intersection( $span )->as_list;
}

sub contains {
    my $self = shift;
    $self->as_set->intersects( $_[0] );
}

sub next {
    my $self = shift;

    if ( exists $self->{next} )
    {
        $self->{next} ( $_[0]->clone );
    }
    else {
        my $span = new DateTime::Span( after => $_[0] );
        return $self->as_set->intersection( $span )->next;
    }
}

sub current {
    my $self = shift;
    return $_[0] if $self->contains( $_[0] );
    $self->previous( $_[0] );
}

sub previous {
    my $self = shift;

    if ( exists $self->{previous} ) 
    {
        return $self->{previous} ( $_[0]->clone );
    }
    else {
        my $span = new DateTime::Span( before => $_[0] );
        return $self->as_set->intersection( $span )->previous;
    }
}

sub closest {
    my $self = shift;
    # return $_[0] if $self->contains( $_[0] );
    my $dt1 = $self->current( $_[0] );
    my $dt2 = $self->next( $_[0] );
    return $dt1 if ( $_[0] - $dt1 ) <= ( $dt2 - $_[0] );
    return $dt2;
}

=head1 NAME

DateTime::Event::Recurrence - Perl DateTime extension for computing basic recurrences

=head1 SYNOPSIS

 use DateTime;
 use DateTime::Event::Recurrence;
 
 my $dt = DateTime->new( year   => 2000,
                         month  => 6,
                         day    => 20,
                  );

 my $r_daily = daily DateTime::Event::Recurrence;

 my $dt_next = $daily->next( $dt );

 my $dt_previous = $daily->previous( $dt );

 my $bool = $daily->contains( $dt );

 my $set_days = $r_daily->as_set( start =>$dt1, end=>$dt2 );

 my @days = $r_daily->as_list( start =>$dt1, end=>$dt2 );

 my $set = $r_daily->intersection($dt_span);
 my $iter = $set->iterator;
 while ( my $dt = $iter->next ) {
     print ' ',$dt->datetime;
 }

=head1 DESCRIPTION

This module will return a DateTime Recurrence object for a given recurrence rule.

=head1 USAGE

=over 4

=item * yearly monthly weekly daily hourly minutely secondly

  my $r_daily = daily DateTime::Event::Recurrence;

Build a DateTime::Event::Recurrence object.

The constructors might take "duration" arguments:

  my $r_daily_at_10 = daily DateTime::Event::Recurrence( hours => 10 );

Note: C<weekly> without arguments returns I<mondays>.

  my $r_tuesdays = weekly DateTime::Event::Recurrence( days => 1 );

A negative duration has the meaning as specified in RFC2445:
it counts backwards from the end of the period.

This is useful for creating recurrences
such as I<last day of month>:

  my $r_last_day_of_month = monthly DateTime::Event::Recurrence( days => -1 );

The constructors do not check for duration overflow, such as specifying
a duration bigger than the period. The behaviour in this case is 
undefined and might change between versions.

=item * as_set

  my $r_set = $r_daily->as_set;

This builds a DateTime::Set recurrence set.

=item * as_list

  my @dt = $r_daily->as_list( $span );

This builds a DateTime array of events that happen inside the span.

=item * previous current next closest

  my $dt = $r_daily->next( $dt );

  my $dt = $r_daily->previous( $dt );

Returns an event related to a datetime.

C<current> returns $dt if $dt is an event. 
It returns previous event otherwise.

C<closest> returns $dt if $dt is an event. 
Otherwise it returns the closest event (previous or next).

=item * contains

  my $bool = $r_daily->contains( $dt );

Verify if a DateTime is a recurrence event.

=back

=head1 AUTHOR

Flavio Soibelmann Glock
fglock@pucrs.br

=head1 CREDITS

The API is under development, with help from the people
in the datetime@perl.org list. Special thanks to Dave Rolsky 
and Ron Hill.

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

DateTime::Set 

DateTime::SpanSet 

=cut
1;

