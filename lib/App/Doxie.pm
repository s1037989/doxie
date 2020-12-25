package App::Doxie;
use Mojo::Base 'Mojolicious';

use Mojo::File 'path';

sub startup {
  my $self = shift;
  
  $self->moniker('doxie');

  push @{$self->renderer->classes}, __PACKAGE__;
  push @{$self->commands->namespaces}, 'App::Doxie::Command';
  push @{$self->plugins->namespaces}, 'App::Doxie::Plugin';

  $self->plugin('Config' => {default => {}});
  $self->plugin('Doxie');

  my $r = $self->routes;
  $r->post('/upload' => sub {
    my $c = shift;
    $c->log->info('uploading...');

    # Check file size
    return $c->render(text => 'File is too big.', status => 200) if $c->req->is_limit_exceeded;

    # Process uploaded file
    return $c->redirect_to('form') unless my $example = $c->param('file');
    my $size = $example->size;
    my $name = $example->filename;
    $c->log->info("Thanks for uploading $size byte file $name.");
    $c->render(text => "Thanks for uploading $size byte file $name.");
  });

  $self->routes->get('/')->to(files => $self->static->paths)->name('index');

  # Log requests for static files
  $self->hook(after_static => sub {
    my $c = shift;
    $c->log->info(sprintf 'GET %s', $c->req->url->path);
  });
  $self->helper(get_files => \&_get_files);
}

sub _get_files {
  my $self = shift;
  my @files;
  foreach my $path ( map { path($_) } grep { $_ && -e $_ } map { ref $_ ? @$_ : $_ } @_ ) {
    if ( -d $path ) {
      $path->list_tree->each(sub{
        push @files, $_->to_rel($path);
      });
    } else {
      push @files, $path;
    }
  }
  return @files;
}

1;

__DATA__
@@ index.html.ep
<p>List of static files available for download</p>
% foreach ( get_files($files) ) {
  <a href="/<%= url_for $_ %>"><%= $_ %></a><br />
% }
