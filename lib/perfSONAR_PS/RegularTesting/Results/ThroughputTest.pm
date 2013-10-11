package perfSONAR_PS::RegularTesting::Results::ThroughputTest;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use Moose;

my $logger = get_logger(__PACKAGE__);

extends 'perfSONAR_PS::RegularTesting::Results::Base';

has 'source'      => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Results::Endpoint');
has 'destination' => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Results::Endpoint');

has 'time'        => (is => 'rw', isa => 'DateTime');

has 'error'        => (is => 'rw', isa => 'Str');

has 'jitter'       => (is => 'rw', isa => 'Num | Undef');
has 'packets_sent' => (is => 'rw', isa => 'Int | Undef');
has 'packets_lost' => (is => 'rw', isa => 'Int | Undef');
has 'throughput'   => (is => 'rw', isa => 'Num');

1;
