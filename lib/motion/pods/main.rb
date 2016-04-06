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
  class Pods
    PODS_ROOT = 'vendor/Pods'
    TARGET_NAME = 'RubyMotion'
    PUBLIC_HEADERS_ROOT = File.join(PODS_ROOT, 'Headers/Public')
    PODS_ROOT_MATCHER = /(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/
    SUPPORT_FILES =
      File.join(PODS_ROOT, "Target Support Files/Pods-#{TARGET_NAME}")

    attr_accessor :podfile

    def initialize(config, vendor_options)
      @config = config
      @vendor_options = vendor_options

      platform =
        case @config.deploy_platform
        when 'MacOSX' then :osx
        when 'iPhoneOS' then :ios
        when 'AppleTVOS' then :tvos
        when 'WatchOS' then :watchos
        else App.fail "Unknown CocoaPods platform: #{@config.deploy_platform}"
        end

      @podfile =
        Pod::Podfile.new(Pathname.new(Rake.original_dir) + 'Rakefile') {}
      @podfile.platform(platform, config.deployment_target)
      @podfile.target(TARGET_NAME)
      cocoapods_config.podfile = @podfile
      cocoapods_config.installation_root =
        Pathname.new(File.expand_path(config.project_dir)) + 'vendor'

      if cocoapods_config.verbose = !!ENV["COCOAPODS_VERBOSE"]
        require 'claide'
      end

      configure_project
    end

    # Adds the Pods project to the RubyMotion config as a vendored project and
    #
    def configure_project
      @config.resources_dirs << resources_dir.to_s

      # TODO: replace this all once Xcodeproj has the proper xcconfig parser.
      return unless xcconfig_hash && ldflags
      configure_xcconfig
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
      @installer ||= Pod::Installer.new(
        cocoapods_config.sandbox,
        @podfile,
        cocoapods_config.lockfile
      )
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

    # TODO: this probably breaks in cases like resource bundles etc, need to test.
    def install_resources
      FileUtils.rm_rf(resources_dir)
      FileUtils.mkdir_p(resources_dir)
      resources.each { |file| install_resource(file, resources_dir) }
    end

    def install_resource(file, resources_dir)
      FileUtils.cp_r(file, resources_dir) if file.exist?
    rescue ArgumentError => exc
      raise unless exc.message =~ /same file/
    end

    def copy_cocoapods_env_and_prefix_headers
      headers = Dir.glob([
        "#{PODS_ROOT}/*.h",
        "#{PODS_ROOT}/*.pch",
        "#{PODS_ROOT}/Target Support Files/**/*.h",
        "#{PODS_ROOT}/Target Support Files/**/*.pch"
      ])

      headers.each do |header|
        src = File.basename(header)
        dst = src.sub(/\.pch$/, ".h")
        dst_path = File.join(PUBLIC_HEADERS_ROOT, "____#{dst}")

        next if File.exist?(dst_path)

        FileUtils.mkdir_p(PUBLIC_HEADERS_ROOT)
        FileUtils.cp(header, dst_path)
      end
    end

    # Helpers
    #-------------------------------------------------------------------------#

    # This is the output that gets shown in `rake config`, so it should be
    # short and sweet.
    #
    def inspect
      cocoapods_config
        .lockfile
        .to_hash["PODS"]
        .map { |pod| pod.is_a?(Hash) ? pod.keys.first : pod }
        .inspect
    end

    def cocoapods_config
      Pod::Config.instance
    end

    def analyzer
      Pod::Installer::Analyzer.new(
        cocoapods_config.sandbox,
        @podfile,
        cocoapods_config.lockfile
      )
    end

    def pods_xcconfig
      path =
        Pathname.new(@config.project_dir) +
        SUPPORT_FILES +
        "Pods-#{TARGET_NAME}.release.xcconfig"
      Xcodeproj::Config.new(path) if path.exist?
    end

    def xcconfig_hash
      return unless pods_xcconfig

      @xcconfig_hash ||= pods_xcconfig.to_hash
    end

    # Do not copy `.framework` bundles, these should be handled through RM's
    # `embedded_frameworks` config attribute.
    #
    def resources
      resources = []
      resource_path =
        Pathname.new(@config.project_dir) +
        SUPPORT_FILES +
        "Pods-#{TARGET_NAME}-resources.sh"

      File.open(resource_path) { |f|
        f.each_line do |line|
          matched = line.match(/install_resource\s+(.*)/)

          next unless matched

          path = (matched[1].strip)[1..-2]

          path.sub!(
            "${BUILD_DIR}/${CONFIGURATION}${EFFECTIVE_PLATFORM_NAME}",
            ".build"
          )

          next if File.extname(path) == ".framework"

          resources << Pathname.new(@config.project_dir) + PODS_ROOT + path
        end
      }
      resources.uniq
    end

    def resources_dir
      Pathname.new(@config.project_dir) + PODS_ROOT + "Resources"
    end

    private

    def configure_xcconfig
      lib_search_paths, lib_search_path_flags = parse_search_paths_and_flags

      # Get the name of all static libraries that come pre-built with pods
      @pre_built_static_libs =
        lib_search_paths.map { |path| static_libraries_in_path(path) }.flatten

      # Collect the Pod products
      pods_libs, libs_to_compile = categorize_libs(lib_search_path_flags)

      @config.libs.concat(libs_to_compile.compact)
      @config.libs.uniq!

      @header_dirs = ["Headers/Public"]

      case @config.deploy_platform
      when "MacOSX" then configure_for_osx(framework_search_paths)
      when "iPhoneOS" then configure_for_iphone(framework_search_paths)
      end

      @config.frameworks.concat(frameworks)
      @config.frameworks.uniq!

      @config.weak_frameworks.concat(weak_frameworks)
      @config.weak_frameworks.uniq!

      @config.vendor_project(PODS_ROOT, :xcode, {
        :target => "Pods-#{TARGET_NAME}",
        :headers_dir => "{#{@header_dirs.join(',')}}",
        :products => pods_libs.map { |lib_name| "lib#{lib_name}.a" },
        :allow_empty_products => (pods_libs.empty? ? true : false),
      }.merge(@vendor_options))
    end

    def categorize_libs(lib_search_path_flags)
      pods_libs = []
      libs_to_compile = []

      linked_libraries.each do |library|
        path = parsed_library_path(library, lib_search_path_flags)

        case path
        when String then libs_to_compile << path
        when :pod then pods_libs << library
        end
      end

      [pods_libs.flatten, libs_to_compile]
    end

    def configure_for_iphone(framework_search_paths)
      pods_root = cocoapods_config.installation_root + "Pods"
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
            header_dir = Pathname.new(path) + "Headers"
            @header_dirs << header_dir.realpath.relative_path_from(pods_root).to_s
            true
          else
            false
          end
        end
      end
    end

    def configure_for_osx(framework_search_paths)
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
    end

    def frameworks
      ldflags.scan(/-framework\s+"?([^\s"]+)"?/).map { |match| match[0] }
    end

    def framework_search_paths
      search_paths = xcconfig_hash["FRAMEWORK_SEARCH_PATHS"]

      return [] unless search_paths

      search_paths.strip!

      return [] if search_paths.empty?

      framework_search_paths = []

      search_paths.scan(/"([^"]+)"/) do |search_path|
        path = search_path.first.gsub!(
          PODS_ROOT_MATCHER,
          "#{@config.project_dir}/#{PODS_ROOT}"
        )
        framework_search_paths << path if path
      end

      # If we couldn't parse any search paths, then presumably nothing was
      # properly quoted, so fallback to just assuming the whole value is one
      # path.
      if framework_search_paths.empty?
        path = search_paths.gsub!(
          PODS_ROOT_MATCHER,
          "#{@config.project_dir}/#{PODS_ROOT}"
        )
        framework_search_paths << path if path
      end

      framework_search_paths
    end

    def ldflags
      xcconfig_hash["OTHER_LDFLAGS"]
    end

    def linked_libraries
      ldflags.scan(/-l"?([^\s"]+)"?/)
    end

    def parse_search_paths_and_flags
      flags = xcconfig_hash["LIBRARY_SEARCH_PATHS"] || ""

      search_paths = []

      flags = flags.split(/\s/).map do |path|
        next if path =~ /(\$\(inherited\))|(\$\{inherited\})/

        path.gsub!(
          /(\$\(PODS_ROOT\))|(\$\{PODS_ROOT\})/,
          File.join(@config.project_dir, PODS_ROOT)
        )

        search_paths << path.delete('"')

        '-L ' << path
      end

      [search_paths, flags.compact.join(' ')]
    end

    def parsed_library_path(library, lib_search_path_flags)
      lib_name = library[0]

      return unless lib_name

      # For CocoaPods 0.37.x or below. This block is marked as deprecated.
      if lib_name.start_with?('Pods-')
        :pod
      elsif @pre_built_static_libs.include?("lib#{lib_name}.a")
        "#{lib_search_path_flags} -ObjC -l#{lib_name}"
      elsif File.exist?("/usr/lib/lib#{lib_name}.dylib")
        "/usr/lib/lib#{lib_name}.dylib"
      else
        :pod
      end
    end

    def static_libraries_in_path(path)
      Dir[File.join(path, "**/*.a")].map { |f| File.basename(f) }
    end

    def weak_frameworks
      ldflags.scan(/-weak_framework\s+([^\s]+)/).map { |match| match[0] }
    end
  end
end
