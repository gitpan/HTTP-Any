package HTTP::Any::Curl;

use strict;
use warnings;

use Net::Curl::Easy qw(/^CURLOPT_/ CURLE_OK CURLE_ABORTED_BY_CALLBACK CURLINFO_EFFECTIVE_URL);


BEGIN {
	Net::Curl::Easy->can('CURLOPT_ACCEPT_ENCODING') or die "Rebuild Net::Curl with libcurl 7.21.6 or newer\n";
	Net::Curl::Easy->can('CURLOPT_COOKIEFILE')      or die "Rebuild curl with Cookies support\n";
}

sub do_http {
	my ($multi_ev, $easy, $url, $opt, $cb) = @_;

	$easy->setopt(CURLOPT_URL, $url);

	my @headers = ();
	@headers = map { $_ . ": " . $$opt{headers}{$_} } keys %{$$opt{headers}} if $$opt{headers};

	if ($$opt{method} and $$opt{method} eq "POST" ) {
		$easy->setopt(CURLOPT_POST, 1);
		unless ($$opt{headers}{"Content-Type"}) {
			push @headers, "Content-Type: application/x-www-form-urlencoded";
		}
		$easy->setopt(CURLOPT_POSTFIELDS, $$opt{body});
	}

	$easy->setopt(CURLOPT_HTTPHEADER, \@headers) if @headers;

	$easy->setopt(CURLOPT_FOLLOWLOCATION, 1);
	$easy->setopt(CURLOPT_MAXREDIRS, 5);


	if ($$opt{cookie}) {
		$easy->setopt(CURLOPT_COOKIEFILE, $$opt{cookie});
		$easy->setopt(CURLOPT_COOKIEJAR,  $$opt{cookie});
	} elsif (defined $$opt{cookie}) {
		$easy->setopt(CURLOPT_COOKIEFILE, "");
	}

	my $on_header = $$opt{on_header};
	my $on_body   = $$opt{on_body};

	$easy->setopt(CURLOPT_WRITEHEADER, \ my $headers);

	my $body;
	$easy->setopt(CURLOPT_FILE, \$body) unless $on_body;

	$easy->setopt(CURLOPT_USERAGENT, $$opt{agent}) if $$opt{agent};
	$easy->setopt(CURLOPT_REFERER, $$opt{referer}) if $$opt{referer};
	$easy->setopt(CURLOPT_TIMEOUT, $$opt{timeout}) if $$opt{timeout};

	if (my $proxy = $$opt{proxy}) {
		my ($h, $p) = split ":", $proxy;
		$easy->setopt(CURLOPT_PROXY,     $h);
		$easy->setopt(CURLOPT_PROXYPORT, $p);
	}

	$easy->setopt(CURLOPT_ACCEPT_ENCODING, "gzip") if $$opt{gzip};

	$easy->setopt(CURLOPT_FORBID_REUSE, $$opt{persistent} ? 0 : 1) if exists $$opt{persistent};

	if (my $max_size = $$opt{max_size}) {
		$easy->setopt(CURLOPT_PROGRESSFUNCTION, sub {
				my ($easy, $dltotal, $dlnow, $ultotal, $ulnow, $uservar) = @_;
				if ($dlnow > $max_size) {
					return 1;
				}
				return 0;
			});
		$easy->setopt(CURLOPT_NOPROGRESS, 0);
	}

	if ($on_header or $on_body) {
		my $cb_write = sub {
			my ($easy, $data, $uservar) = @_;
			if ($on_header) {
				my ($is_success, $headers, $redirects) = headers($easy, $url, $headers);
				my $r = $on_header->($is_success, $headers, $redirects);
				$on_header = undef;
				$r or return 0;
			}
			if ($on_body) {
				$on_body->($data) or return 0;
			}
			return length $data;
		};
		$easy->setopt(CURLOPT_WRITEFUNCTION, $cb_write);
	}

	my $finish = sub {
		my ($easy, $result) = @_;

		if ($headers) {
			my ($is_success, $headers, $redirects) = headers($easy, $url, $headers);
			$$headers{'client-aborted'} = 'max_size' if $result == CURLE_ABORTED_BY_CALLBACK;
			$cb->($is_success, $body, $headers, $redirects);
		} else {
			$cb->(0, undef, { Status => 500, Reason => $easy->error(), URL => $url }, []);
		}

	};
	if ($multi_ev) {
		$multi_ev->($easy, $finish, 4 * 60);
	} else {
		eval {$easy->perform()};
		if ($@) {
			$finish->($easy, $@);
		} else {
			$finish->($easy, CURLE_OK);
		}
	}
}


sub headers {
	my ($easy, $url, $headers) = @_;

	my ($h, @hr) = reverse _headers($url, split /\r?\n\r?\n/, $headers);

	my $status = $$h{Status};
	my $is_success = ($status >= 200 and $status < 300) ? 1 : 0;

	$$h{URL} = $easy->getinfo(CURLINFO_EFFECTIVE_URL);

	return $is_success, $h, \@hr;
}



sub _parse_headers {
	my ($url, $h) = @_;
	my ($status_line, @h) = split /\r?\n/, $h;
	my ($status, $reason) = $status_line =~ m/HTTP\/\d\.\d\s+(\d+)(?:\s+(.+))?/;
	# ToDo Когда $reason не указан, формировать на основе $status?

	my %h = ();
	foreach (@h) {
		my ($k, $v) = split /:\s*/, $_, 2;
		my $h = lc $k;
		push @{$h{$h}}, $v if $v;
	}

	return {
		Status => $status,
		Reason => $reason,
		URL    => $url,
		map { $_ => join ",", @{$h{$_}} } keys %h
	};
}


sub _headers {
	my ($url, $htext, @h) = @_;
	my $h = _parse_headers($url, $htext);
	if (@h) {
		return $h, _headers($$h{location}, @h);
	} else {
		return $h;
	}
}

1;
