package perfSONAR_PS::RegularTesting::Test;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Moose;

has 'description' => (is => 'rw', isa => 'Str');
has 'source'      => (is => 'rw', isa => 'Str');
has 'destination' => (is => 'rw', isa => 'Str');
has 'parameters'  => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Tests::Base');
has 'schedule'    => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Schedulers::Base');

my $logger = get_logger(__PACKAGE__);

sub run_once {
    my ($self) = @_;

    return $self->parameters->run_once({ source => $self->source, destination => $self->destination });
}

sub calculate_next_run_time {
    my ($self) = @_;

    return $self->schedule->calculate_next_run_time();
}

1;
