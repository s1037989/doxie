package App::Doxie;
use Mojo::Base 'Mojolicious';

sub startup {
  my $self = shift;
  
  $self->moniker('doxie');

  push @{$self->commands->namespaces}, 'App::Doxie::Command';
  push @{$self->plugins->namespaces}, 'App::Doxie::Plugin';

  $self->plugin('Config' => {default => {}});
  $self->plugin('Doxie');
}

1;
