# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Plugin API:
# Copyright (C) 2000-2003 Andrea Sterbini, a.sterbini@flashnet.it
# Copyright (C) 2001-2006 Peter Thoeny, peter@thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# This plugin:
# Copyright (C) 2008 Timothe Litt, litt nospam acm dot org
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# For licensing info read LICENSE file in the TWiki root.

=pod

---+ package ThumbnailPlugin

This plugin will make a thumbnail of an attachment when its saved.

Preference variables:
    THUMBNAILPLUGIN_ENABLE : on enables thumbnail creation, default is off

    THUMBNAILPLUGIN_SIZE: Size (pixels) desired, default is 150.

=cut

package Foswiki::Plugins::ThumbnailPlugin;

# Always use strict to enforce variable scoping
use strict;

require Foswiki::Func;    # The plugins API
require Foswiki::Plugins; # For the API version

# $VERSION is referred to by TWiki, and is the only global variable that
# *must* exist in this package.
use vars qw( $VERSION $RELEASE $SHORTDESCRIPTION $debug $pluginName $NO_PREFS_IN_TOPIC );

$VERSION = '$Rev: 15942 (11 Aug 2008) $';

$RELEASE = 'ThumbnailPlugin 1.0';

$SHORTDESCRIPTION = 'Maintains thumbnails of attachements';

$NO_PREFS_IN_TOPIC = 1;

# Name of this Plugin, only used in this module
$pluginName = 'ThumbnailPlugin';

=pod

---++ initPlugin($topic, $web, $user, $installWeb) -> $boolean
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$user= - the login name of the user
   * =$installWeb= - the name of the web the plugin is installed in

=cut

sub initPlugin {
    my( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if( $Foswiki::Plugins::VERSION < 1.026 ) {
        Foswiki::Func::writeWarning( "Version mismatch between $pluginName and Plugins.pm" );
        return 0;
    }


#    my $setting = $Foswiki::cfg{Plugins}{ThumbnailPlugin}{ExampleSetting} || 0;
    $debug = $Foswiki::cfg{Plugins}{ThumbnailPlugin}{Debug} || 0;

    Foswiki::Func::registerTagHandler( 'THUMBNAIL', \&_THUMBNAIL );

    # Plugin correctly initialized
    return 1;
}

# %THUMBNAIL{filename}%
# Returns the filename of the corresponding image file.
# Does not consider path, topic or web.

sub _THUMBNAIL {
    my($session, $params, $theTopic, $theWeb) = @_;

    my $attName = $params->{name} || $params->{_DEFAULT};

    my $imgtypes;
    if( $imgtypes = $params->{imgtypes} ) {
	return "THUMBNAIL: Improper image type" unless( $imgtypes =~ m/^[\w|]+$/ );
    } else {
	$imgtypes = "jpg|JPG|gif|GIF|png|PNG";
    }
    my $variant = $params->{variant};
    unless( $params->{variant} ) {
	my @prefs = split( /[, ]+/, Foswiki::Func::getPreferencesValue( "THUMBNAILPLUGIN_SIZE", $theWeb ));
	$variant = $prefs[0] || 150;
    }

    return "THUMBNAIL: $attName is not a recognized image type" unless( $attName =~ m/^(.*)\.($imgtypes)$/ );

    return "$1_thumbnail_$variant.$2";
}

=pod

---++ beforeAttachmentSaveHandler(\%attrHash, $topic, $web )
   * =\%attrHash= - reference to hash of attachment attribute values
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
This handler is called once when an attachment is uploaded. When this
handler is called, the attachment has *not* been recorded in the database.

The attributes hash will include at least the following attributes:
   * =attachment= => the attachment name
   * =comment= - the comment
   * =user= - the user id
   * =tmpFilename= - name of a temporary file containing the attachment data

*Since:* Foswiki::Plugins::VERSION = 1.025

=cut

sub DISABLE_beforeAttachmentSaveHandler {
    # do not uncomment, use $_[0], $_[1]... instead
    ###   my( $attrHashRef, $topic, $web ) = @_;
    Foswiki::Func::writeDebug( "- ${pluginName}::beforeAttachmentSaveHandler( $_[2].$_[1] )" ) if $debug;
}

=pod

---++ afterAttachmentSaveHandler(\%attrHash, $topic, $web, $error )
   * =\%attrHash= - reference to hash of attachment attribute values
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$error= - any error string generated during the save process
This handler is called just after the save action. The attributes hash
will include at least the following attributes:
   * =attachment= => the attachment name
   * =comment= - the comment
   * =user= - the user id

*Since:* Foswiki::Plugins::VERSION = 1.025

=cut

sub afterAttachmentSaveHandler {
    # do not uncomment, use $_[0], $_[1]... instead
    ###   my( $attrHashRef, $topic, $web ) = @_;
#    Foswiki::Func::writeDebug( "- ${pluginName}::afterAttachmentSaveHandler( $_[2].$_[1] )" ) if $debug;

      my $attr = $_[0];
      my $topic = $_[1];
      my $web = $_[2];
      my $error = $_[3];

      my $attName = $attr->{attachment};

      return unless( $attName =~ m/^(.*)\.(jpg|JPG|gif|GIF|png|PNG)$/ );
      my $name = $1;
      my $type = $2;
      return if( $error || $attName =~ m/_thumbnail\....$/ );

      return unless( Foswiki::Func::getPreferencesFlag( "THUMBNAILPLUGIN_ENABLE", $web ) );

      my $sizelist = Foswiki::Func::getPreferencesValue( "THUMBNAILPLUGIN_SIZE", $web ) || 150;

      eval {
	  require GD;
	  require Image::MetaData::JPEG;
      };die "$pluginName: cant load required modules $@" if( $@ );

      # This user just created the attachment, so I'm not bothering to check for access control errors

      my $data = Foswiki::Func::readAttachment( $web, $topic, $attName );

      foreach my $size (split( /[ ,]+/, $sizelist)) {
	  eval {
	      $data = resize( $data, $size, lc $type );
	  }; if( $@ ) {
	      die "${pluginName}: Unable to resize $attName for thumbnail: $@\n";
	  }
	  
	  my $err;
	  
=for workingapi

          None of these methods will work since addRevisionFromStream is a private method, and
	  there's a deadlock recursively calling saveAttachment due to the topic lock's being held.

	  use File::Temp;
	  my( $fh, $tmpfile ) = File::Temp::tempfile();
	  binmode $fh;
	  print $fh $data or die "Can't write $tmpfile: $!\n";
	  rewind $fh
	      
	      try {
		  $handler->addRevisionFromStream( $fh, $attr->{comment} . "Thumbnail", "WikiAdministrator" );
	      } catch Error::Simple with {
		  $err = shift;
	      };
	  
	  close $fh or die "Can't close $tmpfile: $!\n";
#      unlink( $tmpfile ) if( $tmpfile && -e $tmpfile );
	  
	  try {
	      $handler->addRevisionFromStream( $fh, $attr->{comment} . "Thumbnail", "WikiAdministrator" );
	  } catch Error::Simple with {
	      $err = shift;
	  };
	  
	  my $err = 
	      Foswiki::Func::saveAttachment( $web, topic, "${name}_thumbnail_$size.$type", { hide=>($a->{unref}? 0 : 1),
											   comment=>$attr->{comment},
											   file=>$file,
											   
										       } );
=cut
	      
	  # Break the object and storage abstraction rules and write directly to
          # the attachment storage area.  You probably want autoattach off, as these
          # will otherwise show up on the topic's attachment list - as non-hidden.

          my $fh;
	  my $fname = Foswiki::Func::getPubDir() . "/$web/$topic/${name}_thumbnail_$size.$type";

	  open( $fh, ">", $fname ) or die "Can't open $fname for write: $!\n";
	  binmode $fh;
	  print $fh $data or die "Can't write $fname: $!\n";
            
	  close $fh or die "Can't close $fname: $!\n";
      }

      return;      
  }

=head2 resize( $file, $size )

Resizes C<$file> to C<$size>xC<$size> with transparent margins.

=cut

sub resize {
    my $file = shift;
    my $size = shift;
    my $type = shift;

    my ($image, $hint) = load( $file );

    my ( $width, $height ) = $image->getBounds();

    my $image2 = new GD::Image( $size, $size );

    $image2->transparent( $image2->colorAllocate( 0, 0, 0 ) );

    my $hnw = int( ( $height * $size / $width ) + 0.5 );
    my $wnh = int( ( $width * $size / $height ) + 0.5 );

    my @arg = ( $image, 0, 0, 0, 0, $size, $size, $width, $height );

    if ( $width > $height ) {
        $arg[ 2 ] = int( ( $size - $hnw ) / 2 + 0.5 );
        @arg[ 5, 6 ] = ( $size, $hnw );
    }
    elsif ( $width < $height ) {
        $arg[ 1 ] = int( ( $size - $wnh ) / 2 + 0.5 );
        @arg[ 5, 6 ] = ( $wnh, $size );
    }

    $image2->copyResized( @arg );

    return $image2->png if( $type eq 'png' );
    return $image2->gif if( $type eq 'gif' );
    return $image2->jpeg;
}

=head2 load( $file )

Loads C<$file> and returns a L<GD::Image>.

File is actually data.  It can be a filename - but
in that case, the call to create the JPEG object 
should pass the filename, not a ref.

Handles autorotation - at least for jpeg files.

=cut

sub load {
    my $file = shift;

    my $image;
    die "GD library is too old for ThumbnailPlugin" if ( $GD::VERSION < 1.30 );

    $image = GD::Image->new( $file );

    $Image::MetaData::JPEG::show_warnings = undef;

    my $jpg = new Image::MetaData::JPEG(\$file, qr/APP(0|1)/, 'FASTREADONLY');

    return ($image, 0) unless $jpg;

    my $snum = $jpg->retrieve_app1_Exif_segment(-1);
    for( my $i = 0; $i < $snum; $i++) {
   
	my $seg = $jpg->retrieve_app1_Exif_segment($i);
	my $imgdat = $seg->get_Exif_data('IMAGE_DATA', 'TEXTUAL');
  
	my $o = $imgdat->{'Orientation'};
	next unless $o;

	my $orient = @$o[0];
	if( $orient == 1 ) { # Top, Left-Hand
	    # Normal orientation
	    return ($image, 0);
	} elsif( $orient == 2 ) { # Top, Right-Hand
	    $image->flipHorizontal();
	    return ($image, 1);
	} elsif( $orient == 3 ) { # Bottom, Right-Hand
	    $image->rotate180();
	    return ($image, 1);
	} elsif( $orient == 4 ) { # Bottom, Left-Hand
	    $image->flipVertical();
	    return ($image, 1);
	} elsif( $orient == 5 ) { # Left-Hand, Top
	    $image->flipVertical();
	    return ($image->copyRotate90(), 1);
	} elsif( $orient == 6 ) { # Right-Hand, Top
	    return ($image->copyRotate90(), 1);
	} elsif( $orient == 7 ) { # Right-Hand, Bottom
	    $image->flipHorizontal();
	    return ($image->copyRotate90(), 1);
	} elsif( $orient == 8 ) { # Left-Hand, Bottom
	    return ($image->copyRotate270(), 1);
	}
    }

    # Orientation unknown or not specified

    return ($image, 0);
}

=head2 size( $file )

Returns the width and height of C<$file>.

=cut

sub size {
    my $file = shift;

    my ($image, $hint) = load( $file );

    return $image->getBounds();
}

=pod

The graphics code was leveraged from CGI::Application::PhotoGallery::GD, which
was originally written by Brian Cassidy, and modified for image autoration
by T. Litt, who also made further changes to adapat it for this plugin.

=head1 AUTHOR

Timothe Litt E<lt>litt@acm.org<E<gt>

Copyright 2008 by Timothe Litt

Brian Cassidy E<lt>bricas@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Brian Cassidy

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

1;
