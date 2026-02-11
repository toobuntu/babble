# typed: strict
# frozen_string_literal: true

require "io/console"

# The Waiter module provides methods for generating formatted prompts,
# reading user input, and displaying interactive messages in a terminal
# application. It includes features like ANSI escape sequences for text
# styling and handling special input characters such as arrow keys and
# control commands.
#
# Example usage:
#   require_relative "waiter"
#   Waiter.waiter("run_command")
module Waiter
  # Method to generate a prompt message
  def self.generate_prompt(color_code, bold_text, normal_text)
    # ANSI escape codes for formatting
    color_start = "\e[#{color_code}m"
    bold_start = "\e[1m"
    reset = "\e[0m"

    # Format: colored arrow, bold text, normal text
    "#{color_start}-->#{reset} #{bold_start}#{bold_text}#{reset} #{normal_text}"
  end

  # Method to read a single character from standard input
  def self.read_single_char
    char = $stdin.getch

    case char
    when "\e" # Escape character
      # Attempt to read the rest of the escape sequence
      sequence = $stdin.read_nonblock(3, exception: false) || ""
      sequence = sequence.to_s # Ensure sequence is a string
      full_sequence = char + sequence

      case full_sequence
      when "\e[A" then "Up Arrow"
      when "\e[B" then "Down Arrow"
      when "\e[C" then "Right Arrow"
      when "\e[D" then "Left Arrow"
      when "\e[3~" then "Delete" # Forward Delete on macOS 15 Sequoia
      else "Esc" # No additional characters to read after the escape character
      end
    when "\r", "\n"
      "Enter"
    when "\t"
      "Tab"
    when "\u007F"  # Backward Delete on macOS 15 Sequoia; Forward Delete on macOS <= 14 Sonoma
      "Delete"
    when "\u0008"  # aka "\b"; Backward Delete on macOS <= 14 Sonoma
      "Backspace"
    else
      char # Return the raw character for any other input
    end
  end

  # Method to display the waiter prompt and wait for user input
  def self.waiter(key)
    prompts = {
      "run_command"  => {
        color_code:  33, # Yellow
        bold_text:   "Run",
        normal_text: "command: Press Space bar to continue, or Ctrl-C to exit.",
      },
      "next_section" => {
        color_code:  35, # Magenta
        bold_text:   "Next",
        normal_text: "section: Press Space bar to continue, or Ctrl-C to exit.",
      },
    }

    prompt_data = prompts[key]
    unless prompt_data
      puts "Invalid key: #{key}"
      return 1
    end

    prompt_message = generate_prompt(prompt_data[:color_code], prompt_data[:bold_text], prompt_data[:normal_text])

    print prompt_message
    $stdout.flush

    num_invalid_attempts = 0
    loop do
      # Use ANSI escape sequence to clear the current line
      # print "\r\e[K#{prompt_message} "
      # $stdout.flush
      # state = %x(/bin/stty -g)
      begin
        # %x(/bin/stty raw -echo)
        # $stdin.raw!
        # input = $stdin.getch.tap { |char| exit(1) if char == "\u0003" } # Ctrl-C
        # input = $stdin.raw(&:getc) # getc includes special handling for \n
        # input = $stdin.getch # getch is designed for raw input
        input = read_single_char
        num_invalid_attempts += 1
        # $stdin.raw
        # ensure
        # %x(/bin/stty #{state})
        # $stdin.cooked!
      end

      case input
      when " "
        # puts "\r\e[KContinuing..." # Clear to the end of the current line
        # puts "\r\e[2KContinuing..." # Clear the entire current line
        puts "\nContinuing..."
        break
      when "\u0003" # Ctrl-C
        # puts "\r\e[KExiting..."
        puts "\nExiting..."
        exit(0)
      else
        # K: Clear to the end of the current line
        # print "\r\e[KInvalid input: #{input} (#{num_invalid_attempts}).\n#{prompt_message}"
        # 2K: Clear the entire current line
        # print "\r\e[2KInvalid input: #{input} (#{num_invalid_attempts}).\n#{prompt_message}"
        # F: Move cursor up to beginning of previous line (not ANSI.SYS)
        # print "\r\e[F\e[KInvalid input: #{input} (#{num_invalid_attempts}).\n#{prompt_message}"
        # A: Move cursor up
        print "\r\e[A\e[2KInvalid input (#{num_invalid_attempts}): #{input}.\n#{prompt_message}"
        $stdout.flush
      end
    end
  end
end

# If the script is run directly, execute the waiter method
if __FILE__ == $PROGRAM_NAME
  key = ARGV[0] || "run_command"
  Waiter.waiter(key)
end
