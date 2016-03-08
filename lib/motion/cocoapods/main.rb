# Copyright (c) 2012-2014, Laurent Sansonetti <lrz@hipbyte.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

module Motion
  class CocoaPods
    PODS_ROOT = 'vendor/Pods'
    TARGET_NAME = 'RubyMotion'
    SUPPORT_FILES = File.join(PODS_ROOT, "Target Support Files/Pods-#{TARGET_NAME}")

    attr_accessor :podfile

    def initialize(config, vendor_options)
      @config = config
      @vendor_options = vendor_options

      case @config.deploy_platform
      when 'MacOSX'
        platform = :osx
      when 'iPhoneOS'
        platform = :ios
      when 'AppleTVOS'
        platform = :tvos
      when 'WatchOS'
        platform = :watchos
      else
        App.fail "Unknown CocoaPods platform: #{@config.deploy_platform}"
      end

      @podfile = Pod::Podfile.new(Pathname.new(Rake.original_dir) + 'Rakefile') {}
      @podfile.platform(platform, config.deployment_target)
      @podfile.target(TARGET_NAME)
      cp_config.podfile = @podfile
      cp_config.skip_repo_update = true
      cp_config.installation_root = Pathname.new(File.expand_path(config.project_dir)) + 'vendor'

      if cp_config.verbose = !!ENV['COCOAPODS_VERBOSE']
        require 'claide'
      end

      configure_project
    end

    # Adds the Pods project to the RubyMotion config as a vendored project and
    #
    def configure_project
      @config.resources_dirs << resources_dir.to_s

      # TODO replace this all once Xcodeproj has the proper xcconfig parser.
      if (xcconfig = self.pods_xcconfig_hash) && ldflags = xcconfig['OTHER_LDFLAGS']
        lib_search_path_flags = xcconfig['LIBRARY_SEARCH_PATHS'] || ""
        lib_search_paths = []
        lib_search_path_flags = lib_search_path_flags.split(/\s/).map do |path|
          if path =~ /(\$\(inherited\))|(\$\{inherited\})/
            nil
          else
            path = path.gsub(/(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/, File.join(@config.project_dir, PODS_ROOT))
            lib_search_paths << path.gsub('"', '')
            '-L ' << path
          end
        end.compact.join(' ')

        # Get the name of all static libraries that come pre-built with pods
        pre_built_static_libs = lib_search_paths.map do |path|
          Dir[File.join(path, '**/*.a')].map { |f| File.basename(f) }
        end.flatten

        # Collect the Pod products
        pods_libs = []

        @config.libs.concat(ldflags.scan(/-l"?([^\s"]+)"?/).map { |m|
          lib_name = m[0]
          next if lib_name.nil?
          if lib_name.start_with?('Pods-')
            # For CocoaPods 0.37.x or below. This block is marked as deprecated.
            pods_libs << lib_name
            nil
          elsif pre_built_static_libs.include?("lib#{lib_name}.a")
            "#{lib_search_path_flags} -ObjC -l#{lib_name}"
          elsif File.exist?("/usr/lib/lib#{lib_name}.dylib")
            "/usr/lib/lib#{lib_name}.dylib"
          else
            pods_libs << lib_name
            nil
          end
        }.compact)
        @config.libs.uniq!

        framework_search_paths = []
        if search_paths = xcconfig['FRAMEWORK_SEARCH_PATHS']
          search_paths = search_paths.strip
          unless search_paths.empty?
            search_paths.scan(/"([^"]+)"/) do |search_path|
              path = search_path.first.gsub!(/(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/, "#{@config.project_dir}/#{PODS_ROOT}")
              framework_search_paths << path if path
            end
            # If we couldn't parse any search paths, then presumably nothing was properly quoted, so
            # fallback to just assuming the whole value is one path.
            if framework_search_paths.empty?
              path = search_paths.gsub!(/(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/, "#{@config.project_dir}/#{PODS_ROOT}")
              framework_search_paths << path if path
            end
          end
        end

        header_dirs = ['Headers/Public']
        frameworks = ldflags.scan(/-framework\s+"?([^\s"]+)"?/).map { |m| m[0] }

        case @config.deploy_platform
        when 'MacOSX'
          @config.framework_search_paths.concat(framework_search_paths)
          @config.framework_search_paths.uniq!
          framework_search_paths.each do |framework_search_path|
            frameworks.reject! do |framework|
              path = File.join(framework_search_path, "#{framework}.framework")
              if File.exist?(path)
                @config.embedded_frameworks << path
                true
              else
                false
              end
            end
          end
        when 'iPhoneOS'
          pods_root = cp_config.installation_root + 'Pods'
          # If we would really specify these as ‘frameworks’ then the linker
          # would not link the archive into the application, because it does not
          # see any references to any of the symbols in the archive. Treating it
          # as a static library (which it is) with `-ObjC` fixes this.
          #
          framework_search_paths.each do |framework_search_path|
            frameworks.reject! do |framework|
              path = File.join(framework_search_path, "#{framework}.framework")
              if File.exist?(path)
                @config.libs << "-ObjC '#{File.join(path, framework)}'"
                # This is needed until (and if) CocoaPods links framework
                # headers into `Headers/Public` by default:
                #
                #   https://github.com/CocoaPods/CocoaPods/pull/2722
                #
                header_dir = Pathname.new(path) + 'Headers'
                header_dirs << header_dir.realpath.relative_path_from(pods_root).to_s
                true
              else
                false
              end
            end
          end
        end

        @config.frameworks.concat(frameworks)
        @config.frameworks.uniq!

        @config.weak_frameworks.concat(ldflags.scan(/-weak_framework\s+([^\s]+)/).map { |m| m[0] })
        @config.weak_frameworks.uniq!

        @config.vendor_project(PODS_ROOT, :xcode, {
          :target => "Pods-#{TARGET_NAME}",
          :headers_dir => "{#{header_dirs.join(',')}}",
          :products => pods_libs.map { |lib_name| "lib#{lib_name}.a" },
          :allow_empty_products => (pods_libs.empty? ? true : false),
        }.merge(@vendor_options))
      end
    end

    # DSL
    #-------------------------------------------------------------------------#

    def source(source)
      @podfile.source(source)
    end

    def pod(*name_and_version_requirements, &block)
      @podfile.pod(*name_and_version_requirements, &block)
    end

    # Deprecated.
    def dependency(*name_and_version_requirements, &block)
      @podfile.dependency(*name_and_version_requirements, &block)
    end

    def post_install(&block)
      @podfile.post_install(&block)
    end

    # Installation
    #-------------------------------------------------------------------------#

    def pods_installer
      @installer ||= Pod::Installer.new(cp_config.sandbox, @podfile, cp_config.lockfile)
    end

    # Performs a CocoaPods Installation.
    #
    # For now we only support one Pods target, this will have to be expanded
    # once we work on more spec support.
    #
    # Let RubyMotion re-generate the BridgeSupport file whenever the list of
    # installed pods changes.
    #
    def install!(update)
      pods_installer.update = update
      pods_installer.installation_options.integrate_targets = false
      pods_installer.install!
      install_resources
      copy_cocoapods_env_and_prefix_headers
    end

    # TODO this probably breaks in cases like resource bundles etc, need to test.
    #
    def install_resources
      FileUtils.rm_rf(resources_dir)
      FileUtils.mkdir_p(resources_dir)
      resources.each do |file|
        begin
          FileUtils.cp_r(file, resources_dir) if file.exist?
        rescue ArgumentError => exc
          unless exc.message =~ /same file/
            raise
          end
        end
      end
    end

    PUBLIC_HEADERS_ROOT = File.join(PODS_ROOT, 'Headers/Public')

    def copy_cocoapods_env_and_prefix_headers
      headers = Dir.glob(["#{PODS_ROOT}/*.h", "#{PODS_ROOT}/*.pch", "#{PODS_ROOT}/Target Support Files/**/*.h", "#{PODS_ROOT}/Target Support Files/**/*.pch"])
      headers.each do |header|
        src = File.basename(header)
        dst = src.sub(/\.pch$/, '.h')
        dst_path = File.join(PUBLIC_HEADERS_ROOT, "____#{dst}")
        unless File.exist?(dst_path)
          FileUtils.mkdir_p(PUBLIC_HEADERS_ROOT)
          FileUtils.cp(header, dst_path)
        end
      end
    end

    # Helpers
    #-------------------------------------------------------------------------#

    # This is the output that gets shown in `rake config`, so it should be
    # short and sweet.
    #
    def inspect
      cp_config.lockfile.to_hash['PODS'].map do |pod|
        pod.is_a?(Hash) ? pod.keys.first : pod
      end.inspect
    end

    def cp_config
      Pod::Config.instance
    end

    def analyzer
      cp_config = Pod::Config.instance
      Pod::Installer::Analyzer.new(cp_config.sandbox, @podfile, cp_config.lockfile)
    end

    def pods_xcconfig
      path = Pathname.new(@config.project_dir) + SUPPORT_FILES + "Pods-#{TARGET_NAME}.release.xcconfig"
      Xcodeproj::Config.new(path) if path.exist?
    end

    def pods_xcconfig_hash
      if xcconfig = pods_xcconfig
        xcconfig.to_hash
      end
    end

    # Do not copy `.framework` bundles, these should be handled through RM's
    # `embedded_frameworks` config attribute.
    #
    def resources
      resources = []
      File.open(Pathname.new(@config.project_dir) + SUPPORT_FILES + "Pods-#{TARGET_NAME}-resources.sh") { |f|
        f.each_line do |line|
          if matched = line.match(/install_resource\s+(.*)/)
            path = (matched[1].strip)[1..-2]
            path.sub!("${BUILD_DIR}/${CONFIGURATION}${EFFECTIVE_PLATFORM_NAME}", ".build")
            unless File.extname(path) == '.framework'
              resources << Pathname.new(@config.project_dir) + PODS_ROOT + path
            end
          end
        end
      }
      resources.uniq
    end

    def resources_dir
      Pathname.new(@config.project_dir) + PODS_ROOT + 'Resources'
    end
  end
end
