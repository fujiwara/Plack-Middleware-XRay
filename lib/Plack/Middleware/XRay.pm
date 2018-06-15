package Plack::Middleware::XRay;

use 5.012000;
use strict;
use warnings;
use parent "Plack::Middleware";

use AWS::XRay;

our $VERSION = "0.01";

sub call {
    my ($self, $env) = @_;

    my ($trace_id, $segment_id) = parse_trace_header($env->{HTTP_X_AMZN_TRACE_ID});
    local $AWS::XRay::TRACE_ID   = $trace_id;
    local $AWS::XRay::SEGMENT_ID = $segment_id;
    local $AWS::XRay::ENABLED    = 1;

    AWS::XRay->daemon_host($self->{daemon_host} || "127.0.0.1");
    AWS::XRay->daemon_port($self->{daemon_port} || 2000);

    return AWS::XRay::trace $self->{name}, sub {
        my $segment = shift;

        # fill annotations and metadata
        for my $key (qw/ annotations metadata /) {
            my $code = $self->{"${key}_builder"};
            next unless ref $code eq "CODE";
            $segment->{$key} = {
                %{$self->{$key} || {}},
                %{$code->($env)},
            }
        }

        # HTTP request info
        $segment->{http} = {
            request => {
                method     => $env->{REQUEST_METHOD},
                url        => url($env),
                client_ip  => $env->{REMOTE_ADDR},
                user_agent => $env->{HTTP_USER_AGENT},
            },
        };

        # Run app
        my $res = eval {
            $self->app->($env);
        };
        my $error = $@;
        if ($error) {
            warn $error;
            $res = [
                500,
                ["Content-Type", "text/plain"],
                ["Internal Server Error"],
            ];
        }

        # HTTP response info
        $segment->{http}->{response}->{status} = $res->[0];
        my $status_key =
            $res->[0] >= 500 ? "fault"
          : $res->[0] == 429 ? "throttle"
          : $res->[0] >= 400 ? "error"
          :                    undef;
        $segment->{$status_key} = Types::Serialiser::true if $status_key;

        return $res;
    };
}

sub url {
    my $env = shift;
    return sprintf(
        "%s://%s%s",
        $env->{"psgi.url_scheme"},
        $env->{HTTP_HOST},
        $env->{REQUEST_URI},
    );
}

sub parse_trace_header {
    my $header = shift or return;

    my ($trace_id, $segment_id);
    if ($header =~ /Root=([0-9a-fA-F-]+)/) {
        $trace_id = $1;
    }
    if ($header =~ /Parent=([0-9a-fA-F]+)/) {
        $segment_id = $1;
    }
    return ($trace_id, $segment_id);
}

1;
__END__

=encoding utf-8

=head1 NAME

Plack::Middleware::XRay - Plack middleware for AWS X-Ray tracing

=head1 SYNOPSIS

      use Plack::Builder;
      builder {
          enable "XRay",
              name => "myApp",
          ;
          $app;
      };

      # an example of sampling
      builder {
          local $AWS::XRay::ENABLED = 0; # disable default
          enable_if { rand < 0.01 }      # enable only 1% request
              "XRay"
                  name => "myApp",
          ;
          $app;
      };

=head1 DESCRIPTION

Plack::Middleware::XRay is a middleware for AWS X-Ray.

See also L<AWS::XRay>.

=head1 CONFIGURATION

=head2 name

The logical name of the service that handled the request. Required.

See also L<AWS X-Ray Segment Documents|https://docs.aws.amazon.com/xray/latest/devguide/xray-api-segmentdocuments.html>.

=head2 annotations

L<annotations|https://docs.aws.amazon.com/xray/latest/devguide/xray-api-segmentdocuments.html#api-segmentdocuments-annotations> object with key-value pairs that you want X-Ray to index for search.

=head2 metadata

L<metadata|https://docs.aws.amazon.com/xray/latest/devguide/xray-api-segmentdocuments.html#api-segmentdocuments-metadata> object with any additional data that you want to store in the segment.

=head2 annotations_buidler

Code ref to generate an annotations hashref.

    enable "XRay"
      name => "myApp",
      annotations_buidler => sub {
          my $env = shift;
          return {
              app_id => $env->{HTTP_X_APP_ID},
          };
      },

=head2 metadata_buidler

Code ref to generate a metadata hashref.

=head1 LICENSE

Copyright (C) FUJIWARA Shunichiro.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

FUJIWARA Shunichiro E<lt>fujiwara.shunichiro@gmail.comE<gt>

=cut

