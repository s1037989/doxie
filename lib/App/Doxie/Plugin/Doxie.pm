package App::Doxie::Plugin::Doxie;
use Mojo::Base 'Mojolicious::Plugin';

use Doxie;

sub register {
  my ($self, $app, $conf) = @_;

  $conf->{doxie} ||= $app->config('doxie');
  $conf->{store} ||= $app->config('store');
  delete $conf->{doxie} unless $conf->{doxie};
  delete $conf->{store} unless $conf->{store};

  $app->helper(doxie => sub { state $doxie = Doxie->new(%$conf) });
}
  
1;
