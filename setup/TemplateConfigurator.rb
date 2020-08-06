require 'fileutils'
require 'colored2'

module Pod
  class TemplateConfigurator

    attr_reader :pod_name, :pods_for_podfile, :prefixes, :test_example_file, :username, :email

    def initialize(pod_name)
      @pod_name = pod_name
      @pods_for_podfile = []
      @prefixes = []
      @message_bank = MessageBank.new(self)
    end

    def ask(question)
      answer = ""
      loop do
        puts "\n#{question}?"

        @message_bank.show_prompt
        answer = gets.chomp

        break if answer.length > 0

        print "\nYou need to provide an answer."
      end
      answer
    end

    def ask_with_answers(question, possible_answers)

      print "\n#{question}? ["

      print_info = Proc.new {

        possible_answers_string = possible_answers.each_with_index do |answer, i|
           _answer = (i == 0) ? answer.underlined : answer
           print " " + _answer
           print(" /") if i != possible_answers.length-1
        end
        print " ]\n"
      }
      print_info.call

      answer = ""

      loop do
        @message_bank.show_prompt
        answer = gets.downcase.chomp

        answer = "yes" if answer == "y"
        answer = "no" if answer == "n"

        # default to first answer
        if answer == ""
          answer = possible_answers[0].downcase
          print answer.yellow
        end

        break if possible_answers.map { |a| a.downcase }.include? answer

        print "\nPossible answers are ["
        print_info.call
      end

      answer
    end

    def run
      @message_bank.welcome_message


      # ```
      # Magic configuration summary:
      # -----------------
      # platform :ios
      # framework :swift
      # test :xctest
      # example_app :yes
      # update_main_app_podfle :yes
      # -----------------
      # ```
      
      with_magic = self.ask_with_answers("Do you want to use Magic? If No, proceed at you own risk.", ["Yes", "No"]).to_sym

      case with_magic
        when :yes
          ConfigureWithMagic.perform(configurator: self)

        when :no
          platform = self.ask_with_answers("What platform do you want to use?", ["iOS", "macOS"]).to_sym

          case platform
            when :macos
              ConfigureMacOSSwift.perform(configurator: self)
            when :ios
              framework = self.ask_with_answers("What language do you want to use?", ["Swift", "ObjC"]).to_sym
              case framework
                when :swift
                  ConfigureSwift.perform(configurator: self)

                when :objc
                  ConfigureIOS.perform(configurator: self)
              end
          end
      end

      replace_variables_in_files
      clean_template_files
      rename_template_files
      add_pods_to_podfile
      customise_prefix
      rename_classes_folder
      ensure_carthage_compatibility
      run_pod_install

      case with_magic
        when :yes
          include_in_main_podfile = :yes
        when :no
          include_in_main_podfile = self.ask_with_answers("Would you like to add this module on the MainApp Podfile?", ["Yes", "No"]).to_sym
      end

      if include_in_main_podfile == :yes
        add_pods_to_main_app_podfile
        run_main_app_pod_install
      end

      @message_bank.farewell_message
    end

    #----------------------------------------#

    def ensure_carthage_compatibility
      FileUtils.ln_s('Example/Pods/Pods.xcodeproj', '_Pods.xcodeproj')
    end

    def run_pod_install
      puts "\nRunning " + "pod install".magenta + " on your new library."
      puts ""

      Dir.chdir("Example") do
        system "pod install"
      end
    end

    def run_main_app_pod_install
      puts "\nRunning " + "pod install".magenta + " on the MainApp."
      puts ""

      Dir.chdir("../") do
        system "pod install"
      end
    end

    def clean_template_files
      ["./**/.gitkeep", ".git", ".travis.yml", "configure", "_CONFIGURE.rb", "README.md", "LICENSE", "templates", "setup", "CODE_OF_CONDUCT.md"].each do |asset|
        `rm -rf #{asset}`
      end
    end

    def replace_variables_in_files
      file_names = ['POD_LICENSE', 'POD_README.md', 'NAME.podspec', podfile_path]
      file_names.each do |file_name|
        text = File.read(file_name)
        text.gsub!("${POD_NAME}", @pod_name)
        text.gsub!("${REPO_NAME}", @pod_name.gsub('+', '-'))
        text.gsub!("${USER_NAME}", user_name)
        text.gsub!("${USER_EMAIL}", user_email)
        text.gsub!("${YEAR}", year)
        text.gsub!("${DATE}", date)
        File.open(file_name, "w") { |file| file.puts text }
      end
    end

    def add_pod_to_podfile podname
      @pods_for_podfile << podname
    end

    def add_pods_to_podfile
      podfile = File.read podfile_path
      podfile_content = @pods_for_podfile.map do |pod|
        "pod '" + pod + "'"
      end.join("\n    ")
      podfile.gsub!("${INCLUDED_PODS}", podfile_content)
      File.open(podfile_path, "w") { |file| file.puts podfile }
    end

    def add_pods_to_main_app_podfile
      example_target_template = File.read pod_target_template_path
      example_target_template.gsub!("${POD_NAME}", pod_name)
      example_target_template.gsub!("${POD_NAME_LOWERCASE}", pod_name.downcase)
      
      main_podfile = File.read main_app_podfile_path
      main_podfile.gsub!("${NEW_TARGET_GOES_HERE}", "${NEW_TARGET_GOES_HERE}\n" + example_target_template)
      main_podfile.gsub!("${NEW_POD_GOES_HERE}", ("${NEW_POD_GOES_HERE}\n  " + pod_name.downcase + "_pod"))

      File.open(main_app_podfile_path, "w") { |file| file.puts main_podfile }
    end

    def add_line_to_pch line
      @prefixes << line
    end

    def customise_prefix
      prefix_path = "Example/Tests/Tests-Prefix.pch"
      return unless File.exists? prefix_path

      pch = File.read prefix_path
      pch.gsub!("${INCLUDED_PREFIXES}", @prefixes.join("\n  ") )
      File.open(prefix_path, "w") { |file| file.puts pch }
    end

    def set_test_framework(test_type, extension, folder)
      content_path = "setup/test_examples/" + test_type + "." + extension
      tests_path = "templates/" + folder + "/Example/Tests/Tests." + extension
      tests = File.read tests_path
      tests.gsub!("${TEST_EXAMPLE}", File.read(content_path) )
      File.open(tests_path, "w") { |file| file.puts tests }
    end

    def rename_template_files
      FileUtils.mv "POD_README.md", "README.md"
      FileUtils.mv "POD_LICENSE", "LICENSE"
      FileUtils.mv "NAME.podspec", "#{pod_name}.podspec"
    end

    def rename_classes_folder
      FileUtils.mv "Pod", @pod_name
    end

    def validate_user_details
        return (user_email.length > 0) && (user_name.length > 0)
    end

    #----------------------------------------#

    def user_name
      (ENV['GIT_COMMITTER_NAME'] || github_user_name || `git config user.name` || `<GITHUB_USERNAME>` ).strip
    end

    def github_user_name
      github_user_name = `security find-internet-password -s github.com | grep acct | sed 's/"acct"<blob>="//g' | sed 's/"//g'`.strip
      is_valid = github_user_name.empty? or github_user_name.include? '@'
      return is_valid ? nil : github_user_name
    end

    def user_email
      (ENV['GIT_COMMITTER_EMAIL'] || `git config user.email`).strip
    end

    def year
      Time.now.year.to_s
    end

    def date
      Time.now.strftime "%Y-%m-%d"
    end

    def podfile_path
      'Example/Podfile'
    end

    def main_app_podfile_path
      '../../Podfile'
    end

    def pod_target_template_path
      'POD_TARGET_TEMPLATE'
    end

    #----------------------------------------#
  end
end
