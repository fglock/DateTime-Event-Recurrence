package DateTime::Event::Recurrence;

use strict;
require Exporter;
use Carp;
use DateTime;
use DateTime::Set;
use Params::Validate qw(:all);
use vars qw( $VERSION @ISA );
@ISA     = qw( Exporter );
$VERSION = '0.0';

sub new {
    my $class = shift;
    my %args = validate(
      @_, {
          frequency => { type => SCALAR, optional => 0 },
      }
    );

    return bless \%args, $class;
}

sub as_set {
    my $self  = shift;
    return DateTime::Set->from_recurrence( recurrence =>    
        sub {
            my $tmp = $self->next( $_[0] );
            return $tmp;
        }
    );
}

sub is_event {
    my $self = shift;
    my $dt   = shift;
    croak( "Dates need to be DateTime objects (" . ref($dt) . ")" )
      unless ( ref($dt) eq 'DateTime' );
    return sunrise( $self, $dt ) ? 1 : 0;
}

sub next {
    my $self = shift;
    my $dt   = shift;
    # warn "following_sunrise: dt isa ".ref($dt);
    croak( "Dates need to be DateTime objects (" . ref($dt) . ")" )
      unless ( $dt->isa( 'DateTime' ) );
    my $d = DateTime::Duration->new(
      days => 1,
    );
    # warn "following_sunrise: from ".$dt->datetime;
    if ( $self->is_sunrise($dt) ) {
        my $new_dt = $dt + $d;
        my ( $tmp_rise, undef ) = sunrise( $self, $new_dt );
        # warn "following_sunrise: got ".$tmp_rise->datetime;
        # warn "ERROR ERROR ERROR" if $tmp_rise < $dt;
        return $tmp_rise;
    }
    # warn "following_sunrise: got ???";
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

 my $r_daily = DateTime::Event::Recurrence->new(
	                frequency => 'daily'
		  );

 my $dt_next = $daily->next( $dt );

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

 my $r_daily = DateTime::Event::Recurrence->new(
                        frequency => 'daily'
                  );

frequency can be one of 'yearly', 'monthly', 'daily', 'hourly', 
'minutely', 'secondly'.

=item my $r_set = $sunrise->as_set;

This builds a DateTime::Set recurrence set.

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

