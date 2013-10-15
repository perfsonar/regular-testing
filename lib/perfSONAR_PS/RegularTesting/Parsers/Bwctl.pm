package perfSONAR_PS::RegularTesting::Parsers::Bwctl;

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

perfSONAR_PS::Utils::HTTPS

=head1 DESCRIPTION

A module that provides simple functions for retrieving HTTPS URLs that validate
the certificate.

=head1 API

=cut

use base 'Exporter';
use Params::Validate qw(:all);
use IO::Socket::SSL;
use URI::Split qw(uri_split);
use HTTP::Response;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::RegularTesting::Parsers::Iperf qw(parse_iperf_output);

our @EXPORT_OK = qw( parse_bwctl_output );

my $logger = get_logger(__PACKAGE__);

use DateTime;

=head2 parse_bwctl_output()

=cut

use constant JAN_1970 => 0x83aa7e80;

sub parse_bwctl_output {
    my $parameters = validate( @_, { stdout  => 1,
                                     stderr  => 1,
                                     results => 1, 
                                   });
    my $stdout  = $parameters->{stdout};
    my $stderr  = $parameters->{stderr};
    my $results = $parameters->{results};

    for my $line (split('\n', $stdout)) {
        if (my ($time) = $line =~ /bwctl: start_tool: ([0-9.]+)/) {

            my $time = $time - JAN_1970;

            $results->test_time(DateTime->from_epoch(epoch => $time));
        }
    }

    parse_iperf_output({ stdout => $stdout, stderr => $stderr, results => $results });

    $results->raw_results($stdout);

    return $results;
}

1;

__END__

=head1 SEE ALSO

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-user

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id: Host.pm 5139 2012-06-01 15:48:46Z aaron $

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 COPYRIGHT

Copyright (c) 2008-2009, Internet2

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4
