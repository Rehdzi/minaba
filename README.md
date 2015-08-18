Monaba
======

Wakaba-like imageboard written in Haskell and powered by Yesod. [Demo board](http://haibane.ru).

Features
------
* Multiple file attachment
* Webm and audio support
* AJAX posting and quick reply
* Feed page
* Online user counter
* New posts counter
* Answer map and previews
* Thread and image expanding
* Thread hiding
* Post deletion and editing by user
* Prooflabes as replacement of tripcodes
* Kusaba-like formatting with code highlighting and LaTeX support
* Custom CAPTCHA
* Internationalization
* Country flag support
* Switchable stylesheets
* YouTube, vimeo, coub embedding
* Works fine with JavaScript disabled
* Administration
    - [Hellbanning](http://en.wikipedia.org/wiki/Hellbanning)
    - Banning by IP
    - Thread moderation by OP
    - Flexible account system with customizable groups and permissions
    - Ability to stick and lock threads and to put on auto-sage
    - Moving threads between boards
    - Changing post's parent
    - Modlog which allows to view previous actions
    - Post search by ID and UID

Dependencies
------
* Postgresql >= 9.1
* PHP5 to use GeSHi for code highlighting
* Imagemagick library
* ffmpeg/libav
* exiftool

Required for builiding from source:

* GHC >= 7.6
* cabal-install >= 1.18

Installation
======

    git clone https://github.com/ahushh/Monaba
    cd Monaba

Main config file `config/settings.yml`

The maximum files size is hard coded and can be changed in `Foundation.hs` before building. Default value is 25 MB.

Default login/password: admin

### Download GeoIPCity

    wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz
    gzip -d GeoLiteCity.dat.gz
    cp GeoLiteCity.dat /usr/share/GeoIP/GeoIPCity.dat

Or it can be installed from repositories. You can change the path in `config/settings.yml`

### Download GeSHi

    wget http://sourceforge.net/projects/geshi/files/geshi/GeSHi%201.0.8.11/GeSHi-1.0.8.11.tar.gz
    tar -zxvf GeSHi-1.0.8.11.tar.gz
    mv geshi /your/path/to/geshi

Set your path to GeSHi in `highlight.php`

### Using libav instead of ffmpeg

`sudo ln -s /usr/bin/avconv /usr/bin/ffmpeg`

## Using binary packages

Download dist.7z of the latest verions of Monaba here: https://github.com/ahushh/Monaba/releases/ and unpack it to current directory. 

If it's not working or outdated, try manual build.

## Building manually

Sample list of required packages for debian (probably outdated and not full):

    apt-get install ghc cabal-install zlibc libgeoip-dev libcrypto++-dev libssl-dev postgresql-server-dev-9.1 libmagickwand-dev libmagickcore-dev

### Building executable files

    cabal update
    cabal sandbox init
    cabal install yesod-bin --force-reinstall && cabal install --only-dependencies --force-reinstalls # this takes a while, be patient
    cabal clean && cabal configure && cabal build # and this too

*If you get an error during installation of dependencies*

    Data/Digest/OpenSSL/MD5.hs:49:12: Not in scope: ‘unsafePerformIO’
    cabal: Error: some packages failed to install:
    nano-md5-0.1.2 failed during the building phase. The exception was:
    ExitFailure 1

*this should help*

    cabal fetch nano-md5
    tar -zxvf ~/.cabal/packages/hackage.haskell.org/nano-md5/0.1.2/nano-md5-0.1.2.tar.gz
    patch nano-md5-0.1.2/Data/Digest/OpenSSL/MD5.hs < extra/MD5.hs.patch
    cabal sandbox add-source nano-md5-0.1.2
    cabal install --only-dependencies

## Setup database

Create a database:

    psql -U postgres -c 'create database monabas';

Run the application to initialize database schema:

    ./dist/build/Monaba/Monaba config/settings.yml

Wait until it finish (a few seconds) then stop with Ctrl+C

Fill the database with default values:

     psql -U postgres monabas < init-db.sql

## Configuring Nginx for serving uploaded files

See `extra/nginx.conf`

## Init scripts

init.d script for gentoo: `extra/monaba`

For systemd users: `extra/monaba.service`
