# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Use IOKit to determine whether the device is running on battery power.
# Specifically, read the IOPowerSources functions’ kIOPSBatteryPowerValue, which is the value for key kIOPSPowerSourceStateKey, and indicates that the power source is currently using the internal battery.
def running_on_battery?
  jxa_script = <<-JXA
    #!/usr/bin/env osascript -l JavaScript

    // Import IOKit
    ObjC.import('IOKit');

    // Define constants for power source state
    const POWER_SOURCE_STATE_KEY = "Power Source State";
    const BATTERY_POWER_VALUE = "Battery Power";

    function getPowerSourceState() {
        const powerSourcesInfo = $.IOPSCopyPowerSourcesInfo();
        const sourcesList = $.IOPSCopyPowerSourcesList(powerSourcesInfo);
        
        for (let i = 0; i < sourcesList.length; i++) {
            const source = sourcesList[i];
            const description = $.IOPSGetPowerSourceDescription(powerSourcesInfo, source);
            
            if (description[POWER_SOURCE_STATE_KEY]) {
                return description[POWER_SOURCE_STATE_KEY]; // Return the actual state
            }
        }
        return null; // Return null if no state found
    }

    function isRunningOnBattery() {
        const state = getPowerSourceState();
        return state === BATTERY_POWER_VALUE; // Return true if on battery, false otherwise
    }

    // Call the function and return the result
    const result = isRunningOnBattery();
    result; // This will be returned to the calling Ruby program
  JXA

  # Execute the JXA script and capture the output
  output = `osascript -l JavaScript -e '#{jxa_script}'`
  output.strip == 'true' # Return Boolean true or false based on the output
end

# Example usage
if running_on_battery?
  puts "The device is currently running on battery power."
else
  puts "The device is plugged into power."
end
