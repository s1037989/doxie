package Doxie;
use Mojo::Base -base;

# API Spec:
#   http://help.getdoxie.com/content/doxiego/05-advanced/03-wifi/04-api/Doxie-API-Developer-Guide.pdf

use Mojo::Log;
use Mojo::File qw/path tempfile/;
use Mojo::Loader 'data_section';
use Mojo::Collection 'c';
use Mojo::Template;
use Mojo::UserAgent;

use Date::Simple 'today';

has doxie => sub { shift->discover };
has store => 'public';
has max_concurrent => 2;
has ua => sub { Mojo::UserAgent->new }; # Need to handle if network drops just before or during an operation
has log => sub { Mojo::Log->new };

has '_today';

sub new {
  my $self = shift->SUPER::new(@_);
  $SIG{INT} = sub { $self->cleanup; exit; };
  $self;
}

sub is_connected {
  my $self = shift;
  my $doxie = $self->doxie;
  $self->ua->max_redirects(5)->get("http://$doxie")->res->error ? undef : $self;
}

sub discover {
  my $self = shift;
  die "Auto discovery not implemented, please specify the IP via the doxie parameter\n";
}

sub status {
  my $self = shift->is_connected or return;
  my $doxie = $self->doxie;
  $self->ua->get("http://$doxie/hello.json")->result->json;
}

sub list {
  my $self = shift->is_connected or return;
  my $type = shift;
  my $doxie = $self->doxie;
  c(@{$self->ua->get("http://$doxie/scans.json")->result->json||[]});
}

sub recent {
  my $self = shift->is_connected or return;
  my $type = shift;
  my $doxie = $self->doxie;
  c($self->ua->get("http://$doxie/scans/recent.json")->result->json);
}

sub get_scan {
  my $self = shift->is_connected or return;
  my ($file, $cb) = @_;
  my $doxie = $self->doxie;
  return undef if $self->_max_concurrent || $self->_locked($file);
  $self->log->info("GET $file");
  $self->_lock($file);
  $self->ua->get("http://$doxie/scans/$file" => sub {
    my ($ua, $tx) = @_;
    if ( $tx->res->error ) {
      $self->log->error(sprintf "Error retrieving $file: %s (did you scan a document which interrupts file transfers?)", $tx->res->error->{message});
      $self->_unlock($file);
    } else {
      my $next = $self->_next(scan => $file);
      $self->log->debug("$file => $next");
      $tx->result->content->asset->move_to($next);
      $self->_unlock($file);
      &$cb if $cb && ref $cb eq 'CODE';
    }
  });
}

sub get_thumbnail {
  my $self = shift->is_connected or return;
  my ($file, $cb) = @_;
  my $doxie = $self->doxie;
  return undef if $self->_max_concurrent || $self->_locked($file);
  $self->log->info("GET $file");
  $self->_lock($file);
  $self->ua->get("http://$doxie/thumbnails/$file" => sub {
    my ($ua, $tx) = @_;
    if ( $tx->res->error ) {
      $self->log->error(sprintf "Error retrieving $file: %s (did you scan a document which interrupts file transfers?)", $tx->res->error->{message});
      $self->_unlock($file);
    } else {
      my $next = $self->_next(thumbnail => $file);
      $self->log->debug("$file => $next");
      $tx->result->content->asset->move_to($next);
      $self->_unlock($file);
      &$cb if $cb && ref $cb eq 'CODE';
    }
  });
}

sub del {
  my $self = shift->is_connected or return;
  my (@files) = @_ or return;
  my $doxie = $self->doxie;
  @files = grep { ! $self->_locked($_) } @files;
  if ( $#files == 0 ) {
    $self->log->info(sprintf "DELETE %s", $files[0]);
    $self->ua->delete("http://$doxie/scans/$files[0]")
  } elsif ( $#files > 0 ) {
    $self->log->info(sprintf "DELETES %s", join ',', @files);
    $self->ua->post("http://$doxie/scans/delete.json" => j([@files]));
  }
}

sub pull {
  my $self = shift->is_connected or return;
  $self->_today(today) unless $self->_today;
  $self->_today(undef) unless $self->list->size;
  my $files = @_ ? c(@_) : $self->list->map(sub{$_->{name}});
  $files->each(sub {
    my $file = $_;
    $self->get_scan($file, sub { $self->del($file) });
  });
}

sub active_downloads {
  shift->_store->list({hidden=>1})->grep(qr/\.#/)
}

sub cleanup {
  my $self = shift;
  $self->_store->list_tree->grep(sub{! -s $_})->each(sub{unlink $_});
  $self->_store->list({hidden=>1})->grep(qr/\.#/)->each(sub{unlink $_});
}

sub _store { path(shift->store) }

sub _ymdstore {
  my $self = shift;
  my ($Y, $m, $d) = map { sprintf '%02d', $_ } $self->_today->as_ymd;
  my $path = $self->_store->child($Y, $m, $d);
  $path->make_path;
  return $path;
}

sub _next {
  my ($self, $type, $file) = @_;
  $type = uc($type);
  my ($ext) = (path($file)->basename =~ /\.(\w+)$/);
  my $next = $self->_ymdstore->list->map(sub{path($_)->basename})->grep(qr/^${type}_\d{4}\.$ext/)->sort(sub{$a cmp $b})->last || "${type}_0000.$ext";
  $next =~ s/_(\d+)\./sprintf "_%04d.", $1+1/e;
  $self->_ymdstore->child($next)->spurt('');
  return $self->_ymdstore->child($next);
}

sub _max_concurrent {
  my $self = shift;
  return $self->active_downloads->size >= $self->max_concurrent;
}

sub _lockfile {
  my ($self, $file) = @_;
  $file =~ s/\W/_/g;
  $self->_store->child(".#$file");
}
sub _lock {
  my ($self, $file) = @_;
  $self->_lockfile($file)->spurt('');
}
sub _locked {
  my ($self, $file) = @_;
  return -e $self->_lockfile($file);
}
sub _unlock {
  my ($self, $file) = @_;
  unlink $self->_lockfile($file);
}

1;
