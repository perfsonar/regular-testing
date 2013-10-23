package perfSONAR_PS::RegularTesting::Results::PingTest;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use Moose;

my $logger = get_logger(__PACKAGE__);

use perfSONAR_PS::RegularTesting::Results::Endpoint;

extends 'perfSONAR_PS::RegularTesting::Results::Base';

has 'source'          => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Results::Endpoint', default => sub { return perfSONAR_PS::RegularTesting::Results::Endpoint->new() });
has 'destination'     => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Results::Endpoint', default => sub { return perfSONAR_PS::RegularTesting::Results::Endpoint->new() });

has 'packet_count'      => (is => 'rw', isa => 'Int | Undef');
has 'packet_size'       => (is => 'rw', isa => 'Int | Undef');
has 'packet_ttl'        => (is => 'rw', isa => 'Int | Undef');
has 'inter_packet_time' => (is => 'rw', isa => 'Num | Undef');

has 'test_time'       => (is => 'rw', isa => 'DateTime');

has 'error'           => (is => 'rw', isa => 'Str');

has 'pings'           => (is => 'rw', isa => 'ArrayRef[perfSONAR_PS::RegularTesting::Results::PingTestDatum]', default => sub { [] });

has 'raw_results'     => (is => 'rw', isa => 'Str');

override 'type' => sub { return "ping" };

1;
