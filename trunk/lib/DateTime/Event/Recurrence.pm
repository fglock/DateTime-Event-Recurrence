use strict;

package DateTime::Set::ICal;

use vars qw(@ISA);
# use Carp;

# a "dt::set" with a symbolic string representation 
@ISA = qw( DateTime::Set );

sub set_ical { # include list, exclude list
    my $self = shift;
    # carp "set_ical $_[0] => @{$_[1]}" if @_;
    $self->{as_ical} = [ @_ ];
    $self; 
}

sub get_ical { 
    my $self = shift;
    return unless $self->{as_ical};
    return @{ $self->{as_ical} };  
}

sub clone {
    my $self = shift;
    my $new = $self->SUPER::clone( @_ );
    $new->set_ical( $self->get_ical );
    $new;
}

sub union {
    my $self = shift;
    my $new = $self->SUPER::union( @_ );

    # RFC2445 - op1, op2 must have no 'exclude'
    my (%op1, %op2);
    %op1 = ( $self->get_ical ) if ( UNIVERSAL::can( $self, 'get_ical' ) );
    %op2 = ( $_[0]->get_ical ) if ( UNIVERSAL::can( $_[0], 'get_ical' ) );
    return $new if ( ( exists $op1{exclude} ) ||
		     ( exists $op2{exclude} ) );

    bless $new, 'DateTime::Set::ICal';
    # warn " -- 1 isa @{[%op1]} -- 2 isa @{[%op2]} -- ";
    my @ical;
    @ical = exists $op1{include} ? 
	    @{$op1{include}} : 
	    $self;

    if ( exists $op2{include} )
    {
	push @ical, @{$op2{include}};
    }
    else
    {
	push @ical, @_;  # whatever...
    }
    # warn "union: @ical";
    $new->set_ical( include => [ @ical ] ); 
    $new;
}

sub complement {
    my $self = shift;
    my $new = $self->SUPER::complement( @_ );
    return $new unless @_;

    # RFC2445 - op2 must have no 'exclude'
    my (%op1, %op2);
    %op1 = ( $self->get_ical ) if ( UNIVERSAL::can( $self, 'get_ical' ) );
    %op2 = ( $_[0]->get_ical ) if ( UNIVERSAL::can( $_[0], 'get_ical' ) );
    return $new if ( exists $op2{exclude} );

    bless $new, 'DateTime::Set::ICal';
    # warn " -- 1 isa @{[%op1]} -- 2 isa @{[%op2]} -- ";
    my ( @include, @exclude );
    @include = exists $op1{include} ?
	       @{$op1{include}} :
	       $self;

    @exclude = exists $op1{exclude} ?
               @{$op1{exclude}} :
               ();

    if ( exists $op2{include} )
    {
	push @exclude, @{$op2{include}};
    }
    else
    {
	push @exclude, @_;  # whatever...
    }
    # warn "complement: include @include exclude @exclude";
    $new->set_ical( include => [ @include ], exclude => [ @exclude ] ); 
    $new;
}

package DateTime::Event::Recurrence;

use strict;
use DateTime;
use DateTime::Set;
use DateTime::Span;
use Params::Validate qw(:all);
use vars qw( $VERSION );
$VERSION = '0.13';

use constant INFINITY     =>       100 ** 100 ** 100 ;
use constant NEG_INFINITY => -1 * (100 ** 100 ** 100);

# -------- BASE OPERATIONS

use vars qw( 
    %truncate %next_unit %previous_unit 
    %weekdays %weekdays_1 
    $dur_month $dur_neg_month 
    %memoized_duration
    %ical_name
    %ical_days
);

BEGIN {
    %weekdays =   qw( mo 1 tu 2 we 3 th 4 fr 5 sa 6 su 7 );
    %weekdays_1 = qw( 1mo 1  1tu 2  1we 3  1th 4  1fr 5  1sa 6  1su 7 );
    $dur_month =  new DateTime::Duration( months => 1 );
    $dur_neg_month =  new DateTime::Duration( months => -1 );
    %ical_name =  qw( 
        months BYMONTH   weeks BYWEEK 
        days BYMONTHDAY  hours BYHOUR
        minutes BYMINUTE seconds BYSECOND );
    %ical_days =  qw( 1 MO 2 TU 3 WE 4 TH 5 FR 6 SA 7 SU 
                      -7 MO -6 TU -5 WE -4 TH -3 FR -2 SA -1 SU );
}

# memoization reduces 'duration' creation from >10000 to about 30 per run,
# in DT::E::ICal
#
sub _new_duration {
    # unit, value
    my $dur = \$memoized_duration{$_[0]}{$_[1]};
    unless ( $$dur ) {
        $$dur = new DateTime::Duration( $_[0] => $_[1] );
    }
    return $$dur;
}

sub _add {
    # datetime, unit, value
    my $dur = \$memoized_duration{$_[1]}{$_[2]};
    unless ( $$dur ) {
        $$dur = new DateTime::Duration( $_[1] => $_[2] );
    }
    $_[0]->add_duration( $$dur );
}

# internal subs to get date parameters

sub _week_year {
    # get the internal year number, in 'week' mode
    # the datetime must be near the beginning of the year!
    return $_[0]->clone->add_duration( $dur_month )->year;
}

sub _month {
    # get the internal year+month number
    return 12 * $_[0]->year + $_[0]->month - 1 ;
}


sub _week {
    # get the internal week number
    # $_[1] is the "week start day"
    use integer;
    return ( $_[0]->{local_rd_days} - $_[1] ) / 7;
}

%truncate = (
    (
        map {
              my $name = $_; 
              $name =~ s/s$//;
              $_ => sub { 
                           my $tmp = $_[0]->clone; 
                           $tmp->truncate( to => $name ) 
                        } 
            } qw( years months days hours minutes seconds )
    ),

    weeks   => sub { 
        my $base = $_[0]->clone->truncate( to => 'day' );
        _add( $base, days => - $_[0]->day_of_week 
                             + $weekdays_1{ $_[1]{week_start_day} } );
        while(1) {
            return $base if $base <= $_[0];
            _add( $base, weeks => -1 );
        }
    },

    months_weekly => sub {
        my $tmp;
        my $base = $_[0]->clone->truncate( to => 'month' );
        my $val;
        my $diff;
        while(1) {
            $tmp = $base->clone;
            $val = $weekdays_1{ $_[1]{week_start_day} };
            $diff = $val - $base->day_of_week;
            $diff += 7 if $diff < 0;
            _add( $tmp, days =>  $diff );
            return $tmp if $tmp <= $_[0];
            _add( $base, months => -1 );
        }
    },

    years_weekly => sub {
        my $tmp;
        my $base = $_[0]->clone->add_duration( $dur_month )->truncate( to => 'year' );
        my $val;
        my $diff;
        # print STDERR "start of ".$_[0]->datetime. " $_[1]{week_start_day}\n";
        while(1) {
            $tmp = $base->clone;
            $val = $weekdays_1{ $_[1]{week_start_day} };
            if ( $val ) {
                $diff = $val - $base->day_of_week;
                $diff += 7 if $diff < 0;
            }
            else {
                $diff = ( $weekdays{ $_[1]{week_start_day} } - $base->day_of_week ) % 7;
                $diff -= 7 if $diff > 3;
            }
            _add( $tmp, days =>  $diff );
            return $tmp if $tmp <= $_[0];
            _add( $base, years => -1 );
        }
    },
);

%next_unit = (
    (
        map { 
              my $dur = _new_duration( $_ => 1 );
              $_ => sub { $_[0]->add_duration( $dur ) } 
            } qw( years months weeks days hours minutes seconds )
    ),

    months_weekly => sub {
        my $month = _month( $truncate{months_weekly}->( $_[0], $_[1] ) );
        my $base = $_[0]->clone;
        do {
            _add( $base, days => 21 );
            $_[0] = $truncate{months_weekly}->( $base, $_[1] );
        } while $month >= _month( $_[0] );
        return $_[0];
    },

    years_weekly => sub {
        my $year = _week_year( $truncate{years_weekly}->( $_[0], $_[1] ) );
        my $base = $_[0]->clone;
        do {
            _add( $base,  months => 11 );
            $_[0] = $truncate{years_weekly}->( $base, $_[1] );
        } while $year >= _week_year( $_[0] );
        return $_[0];
    },
);

%previous_unit = (
    ( 
        map { 
              my $dur = _new_duration( $_ => -1 );
              $_ => sub { $_[0]->add_duration( $dur ) } 
            } qw( years months weeks days hours minutes seconds )  
    ),

    months_weekly => sub {
        my $month = _month( $truncate{months_weekly}->( $_[0], $_[1] ) );
        my $base = $_[0]->clone;
        do {
            _add( $base, days => -21 );
            $_[0] = $truncate{months_weekly}->( $base, $_[1] );
        } while $month <= _month( $_[0] );
        return $_[0];
    },

    years_weekly => sub {
        my $year = _week_year( $truncate{years_weekly}->( $_[0], $_[1] ) );
        my $base = $_[0]->clone;
        do {
            _add( $base, months => -11 );
            $_[0] = $truncate{years_weekly}->( $base, $_[1] );
        } while $year <= _week_year( $_[0] );
        return $_[0];
    },
);

# -------- "INTERVAL" OPERATIONS

use vars qw( %truncate_interval %next_unit_interval %previous_unit_interval );

%truncate_interval = (
    # @_ = ( date, $args )

    years   => sub { 
        my $tmp = $_[0]->clone;
        $tmp->truncate( to => 'year' );
        _add( $tmp, years => $_[1]{offset} - ( $_[0]->year % $_[1]{interval} ) );
        _add( $tmp, years => - $_[1]{interval} ) if $tmp > $_[0];
        return $tmp;
    },

    months  => sub { 
        my $tmp = $_[0]->clone;
        my $months = _month( $_[0] );
        $tmp->truncate( to => 'month' );
        _add( $tmp, months => $_[1]{offset} - ( $months % $_[1]{interval} ) );
        _add( $tmp, months => - $_[1]{interval} ) if $tmp > $_[0];
        return $tmp;
    },

    days  => sub { 
        my $tmp = $_[0]->clone;
        #  $_[0]->{local_rd_days}  is not good OO ...
        $tmp->truncate( to => 'day' );
        _add( $tmp, days => $_[1]{offset} - ( $_[0]->{local_rd_days} % $_[1]{interval} ) );
        _add( $tmp, days => - $_[1]{interval} ) if $tmp > $_[0];
        return $tmp;
    },

    hours  => sub {
        my $tmp = $_[0]->clone;
        my $hours = $tmp->{local_rd_days} * 24 + $tmp->hour;
        $tmp->truncate( to => 'hour' );
        _add( $tmp, hours => $_[1]{offset} - ( $hours % $_[1]{interval} ) );
        _add( $tmp, hours => - $_[1]{interval} ) if $tmp > $_[0];
        return $tmp;
    },

    minutes  => sub {
        my $tmp = $_[0]->clone;
        my $minutes = 60 * ( $tmp->{local_rd_days} * 24 + $tmp->hour ) + $tmp->minute;
        $tmp->truncate( to => 'minute' );
        _add( $tmp, minutes => $_[1]{offset} - ( $minutes % $_[1]{interval} ) );
        _add( $tmp, minutes => - $_[1]{interval} ) if $tmp > $_[0];
        return $tmp;
    },

    seconds  => sub {
        my $tmp = $_[0]->clone;
        my $seconds = 86400 * $tmp->{local_rd_days} + $tmp->{local_rd_secs};
        # a 11-digit number (floats have 15-digits in linux/win)
        $tmp->truncate( to => 'second' );
        _add( $tmp, seconds => $_[1]{offset} - ( $seconds % $_[1]{interval} ) );
        _add( $tmp, seconds => - $_[1]{interval} ) if $tmp > $_[0];
        return $tmp;
    },

    weeks   => sub { 
        my $tmp = $truncate{weeks}->( $_[0], $_[1] );
        while ( $_[1]{offset} != ( _week( $tmp, $weekdays_1{ $_[1]{week_start_day} } ) % $_[1]{interval} ) )
        {
            $previous_unit{weeks}->( $tmp, $_[1] );
        }
        return $tmp;
    },

    months_weekly => sub {
        my $tmp = $truncate{years_weekly}->( $_[0], $_[1] );
        while ( $_[1]{offset} != ( _month( $tmp ) % $_[1]{interval} ) )
        {
            $previous_unit{months_weekly}->( $tmp, $_[1] );
        }
        return $tmp;
    },

    years_weekly => sub {
        my $tmp = $truncate{years_weekly}->( $_[0], $_[1] );
        while ( $_[1]{offset} != ( _week_year( $tmp ) % $_[1]{interval} ) ) 
        {
            $previous_unit{years_weekly}->( $tmp, $_[1] );
        }
        return $tmp;
    },
);

%next_unit_interval = (
    (
        map { 
              $_ => sub { 
                           $_[0]->add_duration( $_[1]->{dur_unit_interval} ) 
                        } 
            } qw( years months weeks days hours minutes seconds )
    ),

    months_weekly => sub {
        for ( 1 .. $_[1]->{interval} )
        {
            $next_unit{months_weekly}->( $_[0], $_[1] );
        }
    },

    years_weekly => sub {
        for ( 1 .. $_[1]->{interval} ) 
        {
            $next_unit{years_weekly}->( $_[0], $_[1] );
        }
    },
);

%previous_unit_interval = (
    ( 
        map { 
              $_ => sub { 
                           $_[0]->add_duration( $_[1]->{neg_dur_unit_interval} ) 
                        } 
            } qw( years months weeks days hours minutes seconds )  
    ),

    months_weekly => sub {
        for ( 1 .. $_[1]->{interval} )
        {
            $previous_unit{months_weekly}->( $_[0], $_[1] );
        }
    },

    years_weekly => sub {
        for ( 1 .. $_[1]->{interval} ) 
        {
            $previous_unit{years_weekly}->( $_[0], $_[1] );
        }
    },
);

# -------- CONSTRUCTORS

BEGIN {
    # setup constructors daily, ...
    my @freq = qw(
        days    daily
        hours   hourly
        minutes minutely
        seconds secondly );
    while ( @freq ) 
    {
        my ( $name, $namely ) = ( shift @freq, shift @freq );

        no strict 'refs';
        *{__PACKAGE__ . "::$namely"} =
            sub { use strict 'refs';
                  my $class = shift;
                  my $_args = 
                     _setup_parameters( base => $name, @_ );

                  return DateTime::Set::ICal->empty_set if $_args == -1;
                  my $set = DateTime::Set::ICal->from_recurrence(
                          next => sub { 
                              _get_next( $_[0], $_args ); 
                          },
                          previous => sub { 
                              _get_previous( $_[0], $_args ); 
                          },
                      );

                  my $ical_string = uc( "RRULE:FREQ=$namely" );
                  $ical_string .= $_args->{ical_string} if defined $_args->{ical_string};
                  $set->set_ical( include => [ $ical_string ] ); 
                  # warn $ical_string;
                  return $set;
                };
    }
} # BEGIN


sub weekly {
    my $class = shift;
    my %args = @_;

    my $week_start_day;
    $args{week_start_day} = '1mo' unless $args{week_start_day};
    $args{week_start_day} = '1' . $args{week_start_day} unless $args{week_start_day} =~ /1/;
    $week_start_day = $args{week_start_day};
    die "weekly: invalid week start day ($week_start_day)"
        unless $weekdays_1{ $week_start_day };

    my $_args =
        _setup_parameters( base => 'weeks', %args );
    return DateTime::Set->empty_set if $_args == -1;

    my $ical_string = "RRULE:FREQ=WEEKLY";
    if ( defined $_args->{ical_string} ) 
    {
        my ($by) = $_args->{ical_string} =~ /(BYMONTHDAY=.*?)(;|$)/;
        if ( defined $by ) 
        {
            my ( undef, @days ) = split( /[=,]/, $by );
            # map numbers to rfc2445 weekdays 
            my $by2 = join( ',', map { $ical_days{ $_ } } @days );
            $_args->{ical_string} =~ s/$by/BYDAY=$by2/;
        }
        $ical_string .= $_args->{ical_string};
    }
    # warn $ical_string;

    $_args->{week_start_day} = $week_start_day;

    my $set = DateTime::Set::ICal->from_recurrence(
        next => sub {
            _get_next( $_[0], $_args );
        },
        previous => sub {
            _get_previous( $_[0], $_args );
        }
    );
    $set->set_ical( include => [ $ical_string ] );
    return $set;
}



sub monthly {
    my $class = shift;
    my %args = @_;

    my $week_start_day;
    $week_start_day = $args{week_start_day} = $args{week_start_day} || '1mo';
    die "monthly: invalid week start day ($week_start_day)"
        unless $weekdays_1{ $week_start_day };

    my $_args =
        _setup_parameters( base => 'months', %args );
    return DateTime::Set->empty_set if $_args == -1;

    if ( exists $args{weeks} )
    {
        $_args->{week_start_day} = $week_start_day;

        $_args->{unit} = 'months_weekly';

        if ( $_args->{interval} > 1 ) {
            $_args->{truncate} =               $truncate_interval{$_args->{unit}},
            $_args->{next_unit} =              $next_unit{$_args->{unit}},
            $_args->{previous_unit} =          $previous_unit{$_args->{unit}},
            $_args->{next_unit_interval} =     $next_unit_interval{$_args->{unit}},
            $_args->{previous_unit_interval} = $previous_unit_interval{$_args->{unit}},
        }
        else
        {
            $_args->{truncate} =               $truncate{$_args->{unit}},
            $_args->{next_unit} =              $next_unit{$_args->{unit}},
            $_args->{previous_unit} =          $previous_unit{$_args->{unit}},
            $_args->{next_unit_interval} =     $next_unit{$_args->{unit}},
            $_args->{previous_unit_interval} = $previous_unit{$_args->{unit}},
        }
    }

    my $set = DateTime::Set::ICal->from_recurrence(
        next => sub {
            _get_next( $_[0], $_args );
        },
        previous => sub {
            _get_previous( $_[0], $_args );
        }
    );
    my $ical_string = "RRULE:FREQ=MONTHLY";
    $ical_string .= $_args->{ical_string} if defined $_args->{ical_string};
    $set->set_ical( include => [ $ical_string ] );
    # warn $ical_string;
    return $set;
}


sub yearly {
    my $class = shift;
    my %args = @_;

    my $week_start_day;
    $week_start_day = $args{week_start_day} = $args{week_start_day} || 'mo';
    die "yearly: invalid week start day ($week_start_day)"
        unless $weekdays{ $week_start_day } ||
               $weekdays_1{ $week_start_day };

    my $_args =
        _setup_parameters( base => 'years', %args );
    return DateTime::Set->empty_set if $_args == -1;

    if ( exists $args{weeks} ) 
    {
        $_args->{week_start_day} = $week_start_day;
        $_args->{unit} = 'years_weekly';

        if ( $_args->{interval} > 1 ) {
            $_args->{truncate} =               $truncate_interval{$_args->{unit}},
            $_args->{next_unit} =              $next_unit{$_args->{unit}},
            $_args->{previous_unit} =          $previous_unit{$_args->{unit}},
            $_args->{next_unit_interval} =     $next_unit_interval{$_args->{unit}},
            $_args->{previous_unit_interval} = $previous_unit_interval{$_args->{unit}},
        }
        else
        {
            $_args->{truncate} =               $truncate{$_args->{unit}},
            $_args->{next_unit} =              $next_unit{$_args->{unit}},
            $_args->{previous_unit} =          $previous_unit{$_args->{unit}},
            $_args->{next_unit_interval} =     $next_unit{$_args->{unit}},
            $_args->{previous_unit_interval} = $previous_unit{$_args->{unit}},
        }
    }

    my $set = DateTime::Set::ICal->from_recurrence(
        next => sub {
            _get_next( $_[0], $_args );
        },
        previous => sub {
            _get_previous( $_[0], $_args );
        }
    );
    my $ical_string = "RRULE:FREQ=YEARLY";
    $ical_string .= $_args->{ical_string} if defined $_args->{ical_string};
    $set->set_ical( include => [ $ical_string ] );
    # warn $ical_string;
    return $set;
}


# method( hours => 10 )
# method( hours => 10, minutes => 30 )
# method( hours => [ 6, 12, 18 ], minutes => [ 20, 40 ] )

sub _setup_parameters {
    my %args;
    my @check_day_overflow;
    my @level_unit;
    my @total_level;
    my $span;
    my $base;
    my $interval;
    my $start;
    my $offset;
    my $week_start_day;
    my $ical_string;

    # TODO: @duration instead of $duration
    my $duration;  

    if ( @_ ) {
        %args = @_;
        $base = delete $args{base};
        $interval = delete $args{interval};
        $week_start_day = delete $args{week_start_day};
        my $level = 0;

        my $last_unit = $base;
        $last_unit = 'years_weekly' 
             if $last_unit eq 'years' &&
                exists $args{weeks} ;
        $last_unit = 'months_weekly'
             if $last_unit eq 'months' &&
                exists $args{weeks} ;

        # get 'start' parameter
        $start = $args{start} if exists $args{start};
        $start = $args{after} if exists $args{after} && ! defined $start;
        $start = $args{span}->start if exists $args{span} && ! defined $start;
        if ( defined $start ) {
            undef $start if $start == INFINITY || $start == NEG_INFINITY;
        }

        $ical_string = ";INTERVAL=$interval" if $interval && $interval > 1;
        if ( $week_start_day && $week_start_day ne 'mo' )
        {
            $ical_string .= ";WKST=". uc($week_start_day) 
                if exists $weekdays{$week_start_day};
        }

        for my $unit ( 
                 qw( months weeks days hours minutes seconds nanoseconds ) 
            ) {

            next unless exists $args{$unit};

            $args{$unit} = [ $args{$unit} ] 
                unless ref( $args{$unit} ) eq 'ARRAY';

            # TODO: sort _after_ normalization

            if ( $unit eq 'days' )
            {
                # map rfc2445 weekdays to numbers
                @{$args{$unit}} = map {
                        $_ =~ /[a-z]/ ?
                        $_ = $weekdays{$_} :
                        $_
                    } @{$args{$unit}};
            }
            @{$args{$unit}} = sort { $a <=> $b } @{$args{$unit}};
            # put positive values first
            # warn "Arguments: $unit = @{$args{$unit}}";
            my @tmp = grep { $_ >= 0 } @{$args{$unit}};
            push @tmp, $_ for grep { $_ < 0 } @{$args{$unit}};
            # print STDERR "$unit => @tmp\n";
            @{$args{$unit}} = @tmp;

            $ical_string .= uc( ';' . $ical_name{$unit} . '=' . join(",", @{$args{$unit}} ) ) unless $unit eq 'nanoseconds';

            $duration->[ $level ] = [];

            # TODO: add overflow checks for other units
            # TODO: use a hash instead of if-else

            if ( $unit eq 'seconds' ) {
                    @{$args{$unit}} =
                        grep { $_ < 60 && $_ > -60 } @{$args{$unit}};
            }
            elsif ( $unit eq 'minutes' ) {
                    @{$args{$unit}} =
                        grep { $_ < 60 && $_ > -60 } @{$args{$unit}};
            }
            elsif ( $unit eq 'hours' ) {
                    @{$args{$unit}} =
                        grep { $_ < 24 && $_ > -24 } @{$args{$unit}};
            }
            elsif ( $unit eq 'days' ) {
                # days start in '1'
                for ( @{$args{$unit}} ) {
                    warn 'days cannot be zero' unless $_;
                    $_-- if $_ > 0;
                }
                if ( $base eq 'months' || exists $args{month} ) 
                {   # month day
                    @{$args{$unit}} = 
                        grep { $_ < 31 && $_ > -31 } @{$args{$unit}};

                    # prepare to do more overflow checks at runtime
                    # TODO: remove [$level] in @check_day_overflow

                    for ( 0 .. $#{$args{$unit}} ) {
                        $check_day_overflow[$level][$_] = 1 
                            if ( $args{$unit}[$_] > 27 );
                    }

                }
                elsif ( $base eq 'weeks' || exists $args{week} ) 
                {   # week day
                    @{$args{$unit}} = 
                        grep { $_ < 7 && $_ > -7 } @{$args{$unit}};

                    # adjust week-day to week-start-day
                    my $wkst = $weekdays_1{ $week_start_day };
                    die "invalid week start day" unless $wkst;

                    for ( @{$args{$unit}} ) {
                        if ( $_ >= 0 ) {
                            $_ = $_ - $wkst + 1;
                            # warn "week-day: $_";
                            $_ += 7 if $_ < 0;
                        } 
                    } 

                    # redo argument sort

                    @{$args{$unit}} = sort { $a <=> $b } @{$args{$unit}};
                    # put positive values first
                    my @tmp = grep { $_ >= 0 } @{$args{$unit}};
                    push @tmp, $_ for grep { $_ < 0 } @{$args{$unit}};
                    # print STDERR "$unit => @tmp\n";
                    @{$args{$unit}} = @tmp;

                }
                else 
                {   # year day
                    @{$args{$unit}} =
                        grep { $_ < 366 && $_ > -366 } @{$args{$unit}};
                }
            }
            elsif ( $unit eq 'months' ) {
                # months start in '1'
                for ( @{$args{$unit}} ) {
                    warn 'months cannot be zero' unless $_;
                    $_-- if $_ > 0;
                }
                @{$args{$unit}} =
                    grep { $_ < 12 && $_ > -12 } @{$args{$unit}};
            }
            elsif ( $unit eq 'weeks' ) {
                # weeks start in '1'
                for ( @{$args{$unit}} ) {
                    warn 'weeks cannot be zero' unless $_;
                    $_-- if $_ > 0;
                }
                @{$args{$unit}} =
                    grep { $_ < 53 && $_ > -53 } @{$args{$unit}};
            }

            return -1 unless @{$args{$unit}};  # error - no args left

            push @{ $duration->[ $level ] }, 
                _new_duration( $unit => $_ ) 
                    for @{$args{$unit}};

            push @level_unit, $last_unit;
            $last_unit = $unit;

            delete $args{$unit};

            $level++;
        }

        if ( $start && $interval )
        {
            # get offset 
            my $tmp = $truncate_interval{ $base }->( $start, { interval => $interval, offset => 0, week_start_day => $week_start_day } );
            # print STDERR "start: ".$start->datetime."\n";
            # print STDERR "base: ".$tmp->datetime." $base\n";

            # TODO: - must change this to use the same difference algorithm as
            #   the subs above.

            if ( $base eq 'years' ) {
                $offset = $start->year - $tmp->year;
                $offset = $start->year_week - $tmp->year_week 
                    if exists $args{weeks};
            }
            elsif ( $base eq 'months' ) {
                $offset = _month( $start ) - _month( $tmp );
            }
            elsif ( $base eq 'weeks' ) {
                $offset = _week( $start, $weekdays_1{ $week_start_day } ) - _week( $tmp, $weekdays_1{ $week_start_day } );
            }
            elsif ( $base eq 'days' ) {
                $offset = $start->{local_rd_days} - $tmp->{local_rd_days};
            }
            elsif ( $base eq 'hours' ) {
                $offset = $start->{local_rd_days} * 24 + $start->hour -
                          $tmp->{local_rd_days} * 24   - $tmp->hour;
            }
            elsif ( $base eq 'minutes' ) {
                $offset = 60 * ( $start->{local_rd_days} * 24 + $start->hour ) + $start->minute -
                          60 * ( $tmp->{local_rd_days} * 24 + $tmp->hour )     - $tmp->minute;
            }
            elsif ( $base eq 'seconds' ) {
                $offset = 86400 * $start->{local_rd_days} + $start->{local_rd_secs} -
                          86400 * $tmp->{local_rd_days}   - $tmp->{local_rd_secs};
            }

            $offset = $offset % $interval if defined $interval;

        }
        else 
        {
           $offset = 0;
        }

        # TODO: use $span for selecting elements (using intersection)
        $span = delete $args{span};
        $span = DateTime::Span->new( %args ) if %args;

    }


    my $total_durations = 1;
    if ( $duration ) {
        my $i;

        for ( $i = $#$duration; $i >= 0; $i-- ) {

            if ( $i == $#$duration ) {
                $total_level[$i] = 1;
            }
            else 
            {
                $total_level[$i] = $total_level[$i + 1] * ( 1 + $#{ $duration->[$i + 1] } );
            }
            $total_durations *= 1 + $#{ $duration->[$i] };
        }
    }

    my $unit = $base;
    my $dur_unit = _new_duration( $unit => 1 );
    my $neg_dur_unit = _new_duration( $unit => -1 );

    my $dur_unit_interval;
    my $neg_dur_unit_interval;
    if ( $interval && ( $interval > 1 ) ) 
    {
        $dur_unit_interval = _new_duration( $unit => $interval );
        $neg_dur_unit_interval = _new_duration( $unit => -$interval );

        # warn "base ".$base;

        return {
            unit => $unit,
            truncate => $truncate_interval{ $base },
            previous_unit => $previous_unit{ $base },
            next_unit => $next_unit{ $base },
            previous_unit_interval => $previous_unit_interval{ $base },
            next_unit_interval => $next_unit_interval{ $base },
            duration => $duration, 
            total_durations => $total_durations,
            level_unit => \@level_unit,
            total_level => \@total_level,
            check_day_overflow => \@check_day_overflow,
            dur_unit => $dur_unit,
            neg_dur_unit => $neg_dur_unit,
            interval => $interval,
            offset => $offset,
            dur_unit_interval => $dur_unit_interval,
            neg_dur_unit_interval => $neg_dur_unit_interval,
            ical_string => $ical_string,
        };

    }

    return {
        unit => $unit,
        truncate => $truncate{ $base },
        previous_unit => $previous_unit{ $base },
        next_unit => $next_unit{ $base },
        previous_unit_interval => $previous_unit{ $base },
        next_unit_interval => $next_unit{ $base },
        duration => $duration, 
        total_durations => $total_durations,
        level_unit => \@level_unit,
        total_level => \@total_level,
        check_day_overflow => \@check_day_overflow,
        dur_unit => $dur_unit,
        neg_dur_unit => $neg_dur_unit,
        interval => 1,
        dur_unit_interval => $dur_unit,
        neg_dur_unit_interval => $neg_dur_unit,
        ical_string => $ical_string,
    };
}


# returns undef on any errors
sub _get_occurence_by_index {
    my ( $base, $occurence, $args ) = @_;
    return ( undef, -1 ) if $occurence >= $args->{total_durations};
    my $j;
    my $i;
    my $next = $base->clone;
    for $j ( 0 .. $#{$args->{duration}} ) 
    {
        $i = int( $occurence / $args->{total_level}[$j] );
        $occurence -= $i * $args->{total_level}[$j];

        if ( $args->{duration}[$j][$i]->is_negative )
        {
            $next_unit{ $args->{level_unit}[$j] }->( $next, $args );
        }
        $next->add_duration( $args->{duration}[$j][$i] );

        if ( $args->{check_day_overflow}[$j][$i] &&
             $next->month != $base->month )
        {
            # month overflow (month has no 31st day)
            my $previous = $i * $args->{total_level}[$j] - 1;
            return ( undef, $previous );
        }
    }
    return ( $next, -1 );
}


sub _get_previous {
    my ( $self, $args ) = @_;

    return $self if $self->is_infinite;

    my $base = $args->{truncate}->( $self, $args );

    if ( $args->{duration} ) 
    {
        my $j;
        my $next;
        my ( $tmp, $start, $end );
        my $init = 0;
        my $err;

        INTERVAL: while(1) {
            $args->{previous_unit_interval}->( $base, $args ) if $init;
            $init = 1;

            # binary search
            $start = 0;
            $end = $args->{total_durations} - 1;

            while (1) {
                if ( $end - $start < 3 )
                {
                    for ( $j = $end; $j >= $start; $j-- ) {
                        ( $next, $err ) = _get_occurence_by_index ( $base, $j, $args );

                        unless (defined $next) {
                            if ( $err >= 0 ) { $end = $err; next }
                            next INTERVAL;
                        }
                        return $next if $next < $self;
                    }
                    next INTERVAL;
                }

                $tmp = int( $start + ( $end - $start ) / 2 );
                ( $next, $err ) = _get_occurence_by_index ( $base, $tmp, $args );
                unless (defined $next) {
                    if ( $err >= 0 ) { $end = $err; next }
                    next INTERVAL;
                }

                if ( $next < $self ) {
                    $start = $tmp;
                }
                else {
                    $end = $tmp - 1;
                }
            }
        }
    }

    while ( $base >= $self ) 
    {
        $args->{previous_unit_interval}->( $base, $args );
    }
    return $base;
}



sub _get_next {
    my ( $self, $args ) = @_;

    return $self if $self->is_infinite;

    my $base = $args->{truncate}->( $self, $args );

    if ( $args->{duration} ) 
    {
        my $j;
        my $next;
        my ( $tmp, $start, $end );
        my $init = 0;

        INTERVAL: while(1) {
            $args->{next_unit_interval}->( $base, $args ) if $init;
            $init = 1;

            # binary search
            $start = 0;
            $end = $args->{total_durations} - 1;
                 
            while (1) {
                if ( $end - $start < 3 )
                {
                    for $j ( $start .. $end ) {
                        ( $next ) = _get_occurence_by_index ( $base, $j, $args ) ;
                        next INTERVAL unless defined $next;
                        return $next if $next > $self;
                    }
                    next INTERVAL;
                }

                $tmp = int( $start + ( $end - $start ) / 2 );
                ( $next ) = _get_occurence_by_index ( $base, $tmp, $args ) ;
                next INTERVAL unless defined $next;

                if ( $next > $self ) {
                    $end = $tmp;
                }
                else {
                    $start = $tmp + 1;
                }
            }
        }
    }

    while ( $base <= $self )
    {
        $args->{next_unit_interval}->( $base, $args );
    }
    return $base;
}

1;

__END__

=head1 NAME

DateTime::Event::Recurrence - DateTime::Set extension for create basic recurrence sets

=head1 SYNOPSIS

 use DateTime;
 use DateTime::Event::Recurrence;
 
 my $dt = DateTime->new( year   => 2000,
                         month  => 6,
                         day    => 20,
                       );

 my $daily_set = DateTime::Event::Recurrence->daily;

 my $dt_next = $daily_set->next( $dt );

 my $dt_previous = $daily_set->previous( $dt );

 my $bool = $daily_set->contains( $dt );

 my @days = $daily_set->as_list( start => $dt1, end => $dt2 );

 my $iter = $daily_set->iterator;

 while ( my $dt = $iter->next ) {
     print ' ', $dt->datetime;
 }

=head1 DESCRIPTION

This module provides convenience methods that let you easily create
C<DateTime::Set> objects for various recurrences, such as "once a
month" or "every day".  You can also create more complicated
recurrences, such as "every Monday, Wednesday and Thursday at 10:00 AM
and 2:00 PM".

=head1 USAGE

=over 4

=item * yearly monthly weekly daily hourly minutely secondly

These methods all return a new C<DateTime::Set> object representing
the given recurrence.

  my $daily_set = DateTime::Event::Recurrence->daily;

If no parameters are given, then the set members each occur at the
I<beginning> of the specified recurrence.

For example, by default, the C<monthly()> method returns a set
containing the first day of each month.

Without parameters, the C<weekly()> method returns a set containing
I<Mondays>.

However, you can pass in parameters to alter where these datetimes
fall.  The parameters are the same as those given to the
C<DateTime::Duration> constructor for specifying the length of a
duration.  For example, to create a set representing a daily
recurrence at 10:30 each day, we write this:

  my $daily_at_10_30_set =
      DateTime::Event::Recurrence->daily( hours => 10, minutes => 30 );

To represent every I<Tuesday> (second day of the week):

  my $weekly_on_tuesday_set =
      DateTime::Event::Recurrence->weekly( days => 2 );

A negative duration counts backwards from the end of the period.  This
is done in the same manner as is specified in RFC 2445 (iCal).

This is useful for creating recurrences such as the I<last day of
each month>:

  my $last_day_of_month_set =
      DateTime::Event::Recurrence->monthly( days => -1 );

When days are added to a month the result I<is> checked for month
overflow (such as a nonexisting day 31 or 30), and invalid datetimes
are skipped.

The behaviour when other duration overflows occur is undefined, so
don't do that.  An example of this would be creating a set via the
C<daily()> method and specifying C<< hours => 25 >>.

Invalid parameter values are usually skipped.

The value C<60> for seconds (the leap second) is ignored.  If you
I<really> want the leap second, then specify the second as C<-1>.

You can also provide multiple sets of duration arguments, such as
this:

    my $set = DateTime::Event::Recurrence->daily
                  ( hours =>   [ 10, 14,  -1 ],
                    minutes => [ 15, 30, -15 ],
                  );

This specifies a recurrence occuring every day at these 9 different
times:

  10:15,  10:30,  10:45,   # +10h         ( +15min / +30min / last 15min (-15) )
  14:15,  14:30,  14:45,   # +14h         ( +15min / +30min / last 15min (-15) )
  23:15,  23:30,  23:45,   # last 1h (-1) ( +15min / +30min / last 15min (-15) )

To create a set of recurrences occuring every thirty seconds, we could do this:

    my $every_30_seconds_set =
        DateTime::Event::Recurrence->minutely( seconds => [ 0, 30 ] );

=back

=head2 The "interval" and "start" Parameters

The "interval" parameter represents how often the recurrence rule
repeats. The optional "start" parameter specifies where to start
counting:

    my $dt = DateTime->new( year => 2003, month => 6, day => 15 );

    my $set = DateTime::Event::Recurrence->daily
                  ( interval => 11,
                    hours    => 10,
                    minutes  => 30,
                    start    => $dt,
                  );

This specifies a recurrence that happens at 10:30 on the day specified
by C<< start => $dt >>, and then every 11 days I<before and after>
C<$dt>.  So we get a set like this:

    ...
    2003-06-04T10:30:00,
    2003-06-15T10:30:00,
    2003-06-26T10:30:00,
    ...

In this case, the method is used to specify the unit, so C<daily()>
means that our unit is a day, and C<< interval => 11 >> specifies the
quantity of our unit.

Even if your "start" parameter has a time zone, the returned set will
still be in the floating time zone.

=head2 The "week start day" Parameter

The C<week_start_day> parameter is intended for internal use by the
C<DateTime::Event::ICal> module, for generating RFC2445 recurrences.

The C<week_start_day> represents how the 'first week' of a period is
calculated:

"mo" - this is the default.  The first week is one that starts in
monday, and has I<the most days> in this period.

"tu", "we", "th", "fr", "sa", "su" - The first week is one that starts
in this week-day, and has I<the most days> in this period.  Works for
C<weekly> and C<yearly> recurrences.

"1tu", "1we", "1th", "1fr", "1sa", "1su" - The first week is one that
starts in this week-day, and has I<all days> in this period.  This
works for C<weekly()>, C<monthly()> and C<yearly()> recurrences.

=head2 Time Zones

If you want to specify a time zone for a recurrence, you can do this
by calling C<set_time_zone()> on the returned set:

  my $daily = DateTime::Event::Recurrence->daily;
  $daily->set_time_zone( 'Europe/Berlin' );

You can also pass a C<DateTime.pm> object with a time zone to
the set's C<next()> and C<previous()> methods:

  my $dt = DateTime->today( time_zone => 'Europe/Berlin' );
  my $next = $daily->next($dt);

A recurrence can be affected DST changes, so it would be possible to
specify a recurrence that creates nonexistent datetimes.  Because
C<DateTime.pm> throws an exception if asked to create a non-existent
datetime, please be careful when setting a time zone for your
recurrence.

It might be preferable to always use "UTC" for your sets, and then
convert the returned object to the desired time zone.

=head1 AUTHOR

Flavio Soibelmann Glock
fglock@pucrs.br

=head1 CREDITS

The API was developed with help from the people in the
datetime@perl.org list.

Special thanks to Dave Rolsky, 
Ron Hill and Matt Sisk for being around with ideas.

If you can understand what this module does by reading the docs, you
should thank Dave Rolsky.  If you can't understand it, yell at him.
He also helped removing weird idioms from the code.

Jerrad Pierce came with the idea to move "interval" from
DateTime::Event::ICal to here.

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

DateTime - date and time :)

DateTime::Set - for recurrence-set accessors docs.
You can use DateTime::Set to specify recurrences using callback subroutines.

DateTime::Event::ICal - if you need more complex recurrences.

DateTime::SpanSet - sets of intervals, including recurring sets of intervals.

=cut

