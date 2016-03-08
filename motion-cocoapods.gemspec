# This is just so that the source file can be loaded.
module ::Motion; module Project; class Config
  def self.variable(*); end
end; end; end

require 'date'
$:.unshift File.expand_path('../lib', __FILE__)
require 'motion/cocoapods/version'

Gem::Specification.new do |spec|
  spec.name        = 'motion-cocoapods'
  spec.version     = Motion::CocoaPods::VERSION
  spec.date        = Date.today
  spec.summary     = 'CocoaPods integration for RubyMotion projects'
  spec.description = "motion-cocoapods allows RubyMotion projects to have access to the CocoaPods dependency manager."
  spec.author      = 'Laurent Sansonetti'
  spec.email       = 'lrz@hipbyte.com'
  spec.homepage    = 'http://www.rubymotion.com'
  spec.license     = 'MIT'
  spec.files       = Dir.glob('lib/**/*.rb') << 'README.md' << 'LICENSE'

  spec.add_runtime_dependency 'cocoapods', '>= 1.0.0.beta.4'
end
