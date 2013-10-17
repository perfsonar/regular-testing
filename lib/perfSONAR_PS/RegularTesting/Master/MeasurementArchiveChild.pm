package perfSONAR_PS::RegularTesting::Master::MeasurementArchiveChild;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use IPC::DirQueue;

use Moose;

extends 'perfSONAR_PS::RegularTesting::Master::BaseChild';

has 'measurement_archive' => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::MeasurementArchives::Base');

my $logger = get_logger(__PACKAGE__);

override 'child_main_loop' => sub {
    my ($self) = @_;

    my $queue = IPC::DirQueue->new({ dir => $self->measurement_archive->queue_directory });
    while (1) {
        my $job = $queue->wait_for_queued_job();
        my $results = $job->get_data();

        $logger->debug("Got queued job");

        my ($status, $res) = $self->measurement_archive->store_results(results => $results);
        if ($status == 0) {
            $job->finish();
        }
        else {
            $job->return_to_queue();
        }
    }

    return;
};

1;
