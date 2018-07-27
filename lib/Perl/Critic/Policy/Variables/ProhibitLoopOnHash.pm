package Perl::Critic::Policy::Variables::ProhibitLoopOnHash;
# ABSTRACT: Don't write loops on hashes, only on keys and values of hashes

use strict;
use warnings;
use parent 'Perl::Critic::Policy';

use Carp qw< croak >;
use Perl::Critic::Utils qw< :severities :classification :ppi >;
use List::Util 'first';

use constant 'DESC' => 'Looping over hash instead of hash keys or values';
use constant 'EXPL' => 'You are accidentally looping over the hash itself '
                   . '(both keys and values) '
                   . 'instead of only keys or only values';

# \bfor(each)?(\s+my)?\s*\$\w+\s*\(\s*%
sub supported_parameters { () }
sub default_severity { $SEVERITY_HIGH }
sub default_themes { 'bugs' }
sub applies_to { 'PPI::Token::Word' }

sub violates {
    my ($self, $elem) = @_;

    $elem->isa('PPI::Token::Word')
        and first { $elem eq $_ } qw< for foreach >
        or  return ();

    # This is how we do it:
    # * First, we clear out scoping (like "my" for "foreach my ...")
    # * Second, we clear out topical variables ("foreach $foo (...)")
    # * Then we check if it's a postfix without parenthesis
    # * Lastly, we handle the remaining cases

    # Skip if we do not have the right type of PPI::Statement
    # For example, "$var->{for}" has a PPI::Statement::Expression
    # when leading for() is a PPI::Statement::Compound and
    # a postfix for() is a PPI::Statement
    # This was originally written as: $elem->snext_sibling or return
    $elem->parent && $elem->parent->isa('PPI::Statement::Expression')
        and return;

    # for my $foo (%hash)
    # we simply skip the "my"
    if ( ( my $scope = $elem->snext_sibling )->isa('PPI::Token::Word') ) {
        if ( first { $scope eq $_ } qw< my our local state > ) {
            # for my Foo::Bar $baz (%hash)
            # PPI doesn't handle this well
            # as you can see from the following dump:
            #  PPI::Statement::Compound
            #    PPI::Token::Word    'for'
            #    PPI::Token::Whitespace      ' '
            #    PPI::Token::Word    'my'
            #  PPI::Token::Whitespace        ' '
            #  PPI::Statement
            #    PPI::Token::Word    'Foo::BAR'
            #    PPI::Token::Whitespace      ' '
            #    PPI::Token::Symbol          '$payment'
            #    PPI::Token::Whitespace      ' '
            #    PPI::Structure::List        ( ... )
            #      PPI::Statement::Expression
            #        PPI::Token::Symbol      '@bar'
            #    PPI::Token::Whitespace      ' '
            #    PPI::Structure::Block       { ... }
            #      PPI::Token::Whitespace    ' '

            # First, we need to exhaust spaces
            my $next = $scope;
            $next = $next->next_token
                while $next->next_token->isa('PPI::Token::Whitespace');

            # Then we can use 'next_token' to jump to the next one,
            # even if it's not a sibling
            $elem = $next->next_token;

            # And if it's a variable attribute, we skip it
            $elem->isa('PPI::Token::Word')
                and $elem = $elem->snext_sibling;
        } else {
            # for keys %hash
        }
    }

    # for $foo (%hash)
    # we simply skip the "$foo"
    if ( ( my $topical = $elem->snext_sibling )->isa('PPI::Token::Symbol') ) {
        if (   $topical->snext_sibling
            && $topical->snext_sibling->isa('PPI::Structure::List') )
        {
            $elem = $topical;
        } else {
            # for $foo (%hash);
        }
    }

    # for %hash
    # (postfix without parens)
    _check_symbol_or_cast( $elem->snext_sibling )
        and return $self->violation( DESC(), EXPL(), $elem );

    # for (%hash)
    if ( ( my $list = $elem->snext_sibling )->isa('PPI::Structure::List') ) {
        my @children = $list->schildren;
        @children > 1
            and croak "List has multiple significant children ($list)";

        if ( ( my $statement = $children[0] )->isa('PPI::Statement') ) {
            my @statement_args = $statement->schildren;

            _check_symbol_or_cast( $statement_args[0] )
                and return $self->violation( DESC(), EXPL(), $statement );
        }
    }

    return ();
}

sub _check_symbol_or_cast {
    my $arg = shift;

    # This is either a variable
    # or casting from a variable (or from a statement)
    $arg->isa('PPI::Token::Symbol') && $arg =~ /^%/xms
        or $arg->isa('PPI::Token::Cast') && $arg eq '%'
        or return;

    my $next_op = $arg->snext_sibling;

    # If this is a cast, we want to exhaust the block
    # the block could include anything, really...
    if ( $arg->isa('PPI::Token::Cast') && $next_op->isa('PPI::Structure::Block') ) {
        $next_op = $next_op->snext_sibling;
    }

    # Safe guard against operators
    # for ( %hash ? ... : ... );
    $next_op && $next_op->isa('PPI::Token::Operator')
        and return;

    return 1;
}

1;

__END__

=head1 DESCRIPTION

When "looping over hashes," we mean looping over hash keys or hash values. If
you forgot to call C<keys> or C<values> you will accidentally loop over both.

    foreach my $foo (%hash) {...}        # not ok
    action() for %hash;                  # not ok
    foreach my $foo ( keys %hash ) {...} # ok
    action() for values %hash;           # ok

An effort is made to detect expressions:

    action() for %hash ? keys %hash : ();                             # ok
    action() for %{ $hash{'stuff'} } ? keys %{ $hash{'stuff'} } : (); # ok

(Granted, the second example there doesn't make much sense, but I have found
a variation of it in real code.)

=head1 CONFIGURATION

This policy is not configurable except for the standard options.

=head1 AUTHOR

Sawyer X, C<xsawyerx@cpan.org>

=head1 THANKS

Thank you to Ruud H.G. Van Tol.

=head1 SEE ALSO

L<Perl::Critic>
