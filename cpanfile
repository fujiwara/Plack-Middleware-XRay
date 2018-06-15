requires 'perl', '5.012000';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

requires 'Plack::Middleware';
requires 'AWS::XRay';

