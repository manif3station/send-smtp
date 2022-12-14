package Send::SMTP;

use strict;
use warnings;

use Email::Address::XS;
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP::TLS;
use Email::MIME;
use File::MimeInfo::Magic;
use MIME::Types;
use Try::Tiny;

my $file_count = 0;

sub attachment {
    my ( $content, %options ) = @_;

    return if !$content;

    open my $fh, '<', \$content;

    my $mime_type = $options{mime_type} // mimetype($fh) // 'text/plain';

    my $ext = $options{file_ext} // MIME::Types->new->type();

    my $file = $options{filename} // sprintf 'file%d.%s', $file_count++,
        $ext ? ( $ext->extensions )[0] : 'txt';

    my $encoding = $options{encoding} // (
        $mime_type =~ m/(text|json|svg)/ ? 'quoted-printable' : 'base64' );

    my $charset = $options{charset} // 'UTF-8';

    return (
        attributes => {
            content_type => $mime_type,
            filename     => $file,
            disposition  => 'attachment',
            encoding     => $encoding,
            ( charset => $charset ) x !!$charset,
        },
        body_str => $content,
    );
}

sub email_address {
    my ($email) = @_;
    return $email if !$email || !UNIVERSAL::isa( $email, 'HASH' );
    return Email::Address::XS->new( @$email{qw(name email)} )->format;
}

sub email_list {
    my ($list) = @_;
    return          if !$list;
    $list = [$list] if !UNIVERSAL::isa( $list, 'ARRAY' );
    return [ grep {$_} map { email_address $_ } @$list ];
}

sub email {
    my ( $class, %info ) = @_;

    my $from       = $info{from} or die "Missing send from";
    my $to         = $info{to}   or die "Missing send to";
    my $cc         = $info{cc};
    my $bcc        = $info{bcc};
    my $subject    = $info{subject};
    my $text       = $info{text};
    my $html       = $info{html};
    my @attachment = @{ $info{attachment} // [] };

    $from = email_address $from;
    $to   = email_list $to;
    $cc   = email_list $cc;
    $bcc  = email_list $bcc;

    my @parts
        = grep {$_} map { Email::MIME->create( attachment $_) } @attachment;

    my $email = Email::MIME->create(
        header_str => [
            From => $from,
            To   => $to,
            ( Cc  => $cc ) x !!$cc,
            ( Bcc => $bcc ) x !!$bcc,
            Subject => $subject,
        ],
        parts => [ ($text) x !!$text, ($html) x !!$html, @parts, ]
    );

    try {
        sendmail $email => {
            transport => Email::Sender::Transport::SMTP::TLS->new(
                host     => $info{server}{host},
                port     => $info{server}{port},
                username => $info{server}{username},
                password => $info{server}{password},
            )
        };
    }
    catch {
        my $error = $_;
        if ( $ENV{DEBUG_SEND_EMAIL} ) {
            warn $error;
        }
    };

    return;
}

1;
