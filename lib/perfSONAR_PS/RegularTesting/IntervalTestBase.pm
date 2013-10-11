package perfSONAR_PS::RegularTesting::IntervalTestBase;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Moose;

extends 'perfSONAR_PS::RegularTesting::TestBase';

has 'interval' => (is => 'rw', isa => 'Int');
has 'timeout'  => (is => 'rw', isa => 'Int');

my $logger = get_logger(__PACKAGE__);

after 'init' => sub {
    my ($self) = @_;

    unless ($self->interval) {
        die("'interval' not specified");
    }
};

override 'run_tests' => sub {
    my ($self) = @_;

    my $next_runtime = time;

    while (1) {
        while ((my $sleep_time = $next_runtime - time) > 0) {
            $logger->debug("Waiting for ".$sleep_time." seconds for next runtime of test ".$self->description);
            sleep($sleep_time);
        }

        $next_runtime = time + $self->interval;

        $logger->debug("Running test: ".$self->description);
        my $results;
        eval {
            if ($self->timeout) {
                local $SIG{ALRM} = sub { die "Test timed out" };
                alarm $self->timeout;
            }

            $results = $self->run_once();
            alarm 0;
        };
        if ($@) {
            my $error = $@;
            $logger->error("Problem running test: ".$self->description.": ".$error);
            #$self->error($@);
        };

        #$self->store_results($results);
    }

    return;
};

sub run_once {
    my ($self) = @_;

    die("run_once needs to be overridden");
}

1;
