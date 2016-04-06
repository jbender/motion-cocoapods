require 'date'
$:.unshift File.expand_path('../lib', __FILE__)
require 'motion/pods/version'

Gem::Specification.new do |spec|
  spec.name = 'motion-pods'
  spec.version = Motion::Pods::VERSION
  spec.date = Date.today
  spec.summary = 'CocoaPods integration for RubyMotion projects'
  spec.description =
    "motion-pods allows RubyMotion projects to have access to the CocoaPods " \
    "dependency manager."
  spec.author = ['Laurent Sansonetti', 'Jonathan Bender']
  spec.email = ['lrz@hipbyte.com', 'jlbender@gmail.com']
  spec.homepage = 'https://github.com/jbender/motion-pods'
  spec.license = 'MIT'
  spec.files = Dir.glob('lib/**/*.rb') << 'README.md' << 'LICENSE'

  spec.add_runtime_dependency 'cocoapods', '>= 1.0.0.beta.6'
end
