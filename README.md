# motion-pods
[![Gem](https://img.shields.io/gem/v/motion-pods.svg)](https://rubygems.org/gems/motion-pods)
[![Build Status](https://img.shields.io/travis/jbender/motion-pods.svg)](https://travis-ci.org/jbender/motion-pods)
[![Code Climate](https://img.shields.io/codeclimate/github/jbender/motion-pods.svg)](https://codeclimate.com/github/jbender/motion-pods)

A fork of [motion-cocoapods](https://github.com/HipByte/motion-cocoapods), motion-pods allows RubyMotion projects to integrate with the
[CocoaPods](https://cocoapods.org/) dependency manager.


## Installation

```
$ [sudo] gem install motion-pods
```

Or if you use Bundler:

```ruby
gem 'motion-pods'
```


## Setup

1. Edit the `Rakefile` of your RubyMotion project and add the following require
   line:

   ```ruby
   require 'rubygems'
   require 'motion-pods'
   ```

2. Still in the `Rakefile`, set your dependencies using the same language as
   you would do in [Podfiles](https://guides.cocoapods.org/syntax/podfile.html).

   ```ruby
   Motion::Project::App.setup do |app|
     # ...
     app.pods do
       pod 'AFNetworking'
     end
   end
   ```

3. If this is the first time using CocoaPods on your machine, you'll need to
   let CocoaPods do some setup work with the following command:

   ```
   $ [bundle exec] pod setup
   ```


## Tasks

To tell motion-pods to download your dependencies, run the following rake
task:

```
$ [bundle exec] rake pod:install
```

That’s all. The build system will properly download the given pods and their
dependencies. On the next build of your application it will pod the pods and
link them to your application executable.

If the `vendor/Podfile.lock` file exists, this will be used to install specific
versions. To update the versions, use the following rake task:

```
$ [bundle exec] rake pod:update
```

## Options

If necessary, you can pass `vendor_project` options to the `pods` configuration
method. These options are described [here](http://www.rubymotion.com/developer-center/guides/project-management/#_vendoring_3rd_party_libraries).
For instance, to only generate BridgeSupport metadata for a single pod, which
might be needed if a dependency that you’re not using directly is causing issues
(such as C++ headers), you can specify that like so:

```ruby
   Motion::Project::App.setup do |app|
     app.pods :headers_dir => 'Headers/AFNetworking' do
       pod 'AFNetworking'
       # ...
     end
   end
```

By default the output of CocoaPods doing its work is silenced. If, however, you
would like to see the output, you can set the `COCOAPODS_VERBOSE` env variable:

```
$ [bundle exec] rake pod:install COCOAPODS_VERBOSE=1
```

As part of the install and update tasks, the specification repostories will get
updated. You can disable this with the `COCOAPODS_NO_REPO_UPDATE` env variable:

```
$ [bundle exec] rake pod:install COCOAPODS_NO_REPO_UPDATE=1
```


## Contribute

1. Setup a local development environment.

   ```
   $ git clone git://github.com/jbender/motion-pods.git
   $ cd motion-pods
   $ [bundle exec] rake bootstrap
   ```

2. Verify that all the tests are passing.

   ```
   $ [bundle exec] rake spec
   ```

3. Create your patch and send a
   [pull-request](https://help.github.com/send-pull-requests/).


## License

  Copyright (c) 2012-2015, HipByte (lrz@hipbyte.com) and contributors.
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:

  1. Redistributions of source code must retain the above copyright notice, this
     list of conditions and the following disclaimer.
  2. Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
