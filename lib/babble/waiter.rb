# typed: strict
# frozen_string_literal: true

require "io/console"

module Babble
  module Waiter
    class << self
      def generate_prompt(color_code, bold_text, normal_text)
        color_start = "\e[#{color_code}m"
        bold_start = "\e[1m"
        reset = "\e[0m"

        "#{color_start}-->#{reset} #{bold_start}#{bold_text}#{reset} #{normal_text}"
      end

      def read_single_char
        char = $stdin.getch

        case char
        when "\e"
          sequence = $stdin.read_nonblock(3, exception: false) || ""
          sequence = sequence.to_s
          full_sequence = char + sequence

          case full_sequence
          when "\e[A" then "Up Arrow"
          when "\e[B" then "Down Arrow"
          when "\e[C" then "Right Arrow"
          when "\e[D" then "Left Arrow"
          when "\e[3~" then "Delete"
          else "Esc"
          end
        when "\r", "\n"
          "Enter"
        when "\t"
          "Tab"
        when "\u007F"
          "Delete"
        when "\u0008"
          "Backspace"
        else
          char
        end
      end

      def waiter(key, continuation_message: "Continuing...")
        prompts = {
          "run_command"  => {
            color_code:  33,
            bold_text:   "Run",
            normal_text: "command: Press Space bar to continue, or Ctrl-C to exit.",
          },
          "next_section" => {
            color_code:  35,
            bold_text:   "Next",
            normal_text: "section: Press Space bar to continue, or Ctrl-C to exit.",
          },
        }

        prompt_data = prompts[key]
        unless prompt_data
          puts "Invalid key: #{key}"
          return 1
        end

        prompt_message = generate_prompt(
          prompt_data[:color_code],
          prompt_data[:bold_text],
          prompt_data[:normal_text]
        )

        puts prompt_message

        loop do
          input = read_single_char

          case input
          when " "
            puts continuation_message
            break
          when "\u0003"
            puts "\nExiting..."
            exit(0)
          end
        end

        0
      end
    end
  end
end
