needs 'Flow Cytometry/Cytometers'

module Cytometers
  # module for the Sony SH800S cytometer.
  module SonySH800S
    include Cytometer

    CYTOMETER_NAME = 'Sony SH800S'
    TEMPLATE_DIR = ''

    # TODO: handle secrets differently
    LOGIN_USER = 'dummy_user'
    LOGIN_PASSWORD = 'dummy_password'

    TUBE_LABEL_STUB = "Tube - %d"

    DEFAULT_LOCATION = "NanoES 380B"

    def cytometer_name
      CYTOMETER_NAME
    end

    def location
      DEFAULT_LOCATION
    end

    def image_path
      "#{FACS_IMAGE_PATH}/sony_sh800s"
    end

    def path_to(filename, extension='png')
      "#{image_path}/#{filename}.#{extension}"
    end

    def go_to_facs_and_login
      show do
        title "Go to the FACS"
        note "Take the cooler and the box with you."
        note "The FACS is in #{location}."
      end

      show do
        title "Log into the FACS instrument"

        note "If the software is logged out, log back in with the following credentials:"
        note "User: #{LOGIN_USER}"
        note "Password: #{LOGIN_PASSWORD}"
      end
    end

    def set_up_instrument(experiment_name:, template:, events_to_record:, target_events:, args:{})
      insert_tube_holder

      create_new_experiment(
        name: experiment_name,
        template: template
      )

      verify_settings(
        events_to_record: events_to_record
      )

      set_up_sorting(
        target_events: target_events,
        args: args
      )
    end

    def insert_tube_holder
      show do
        title "Insert sample tube holder"

        note "Find the correct sample tube holder based on the type of tube " \
                "containing the cells to be sorted."
        image path_to('all_sample_tube_holders')

        note "Place the sample tube holder in the instrument. " \
                "It is held in place by a magnet."
        image path_to('sample_tube_location')
      end
    end

    def create_new_experiment(name:, template:)
      show do
        title "Create a new experiment"

        note "If the <b>Create Experiment</b> window is not displayed, " \
                "click <b>New</b> on the <b> File</b> tab of the ribbon."

        image path_to('new_experiment')
        note "1. Under <b>My Templates</b>, click " \
                "<span style=\"background-color:yellow\"><b>#{template}</b></span>."

        note "2. Enter <span style=\"background-color:yellow\"><b>#{name}</b>" \
                "</span> in <b>Name</b>."

        note "3. Click <b>Create New Experiment</b>."
      end
    end

    def verify_settings(events_to_record:)
      show do
        title "Verify settings"

        note "Verify that <b>Sample Stop Condition</b> is set to <b>Recording and Sorting</b>."
        note "Under <b>Recording</b>, verify that the <b>Stop Condition</b> is set to " \
                "<b>Event Count</b>."
        note "Verify that <b>Stop Value</b> is set to " \
                "<b>#{number_with_delimiter(events_to_record)}</b>."
        image path_to('stop_condition')
      end
    end

    def set_up_sorting(target_events: nil, args:{})
      args = default_sort_settings.merge(args)
      args[:left_stop_value] = target_events if target_events.present?
      [:left_stop_value, :right_stop_value].each do |stop_value|
        args[stop_value] = number_with_delimiter(args[stop_value])
      end
      auto_record = args[:auto_record] ? "&#10003;" : "&#9634;"
      sort_settings_table = [
        ["","","","","<b>L</b>","<b>R</b>"],
        [
          "<b>Method:</b>",
          args[:method],
          "#{auto_record} Auto Record",
          "<b>To Sort:</b>",
          args[:left_gate],
          args[:right_gate]
        ],
        [
          "<b>Mode:</b>",
          args[:mode],
          args[:cell_size],
          "<b>Stop Value:</b>",
          args[:left_stop_value],
          args[:right_stop_value]
        ]
      ]

      show do
        title "Set up sorting"

        note "Show/hide the <b>Sort Control</b> by clicking the <b>^</b> along " \
                "the bottom edge of the screen."

        note 'Select or verify the following settings:'
        table sort_settings_table
      end
    end

    def default_sort_settings
      {
        method: "2 Way Tubes",
        mode: "Purity",
        cell_size: "Regular Cell",
        left_gate: "FITC positive",
        right_gate: "",
        left_stop_value: "&nbsp;" * 12,
        right_stop_value: "&nbsp;" * 12,
        auto_record: true
      }
    end

    def set_and_run_tube(item:, tube_label:, tube_ct:, sort:)
      set_tube(item: item, tube_label: tube_label, tube_ct: tube_ct, sort: sort)
      load_tube(item: item, tube_label: tube_label, sort: sort)
    end

    def sort_tube(item:, tube_label:, default_to_sort:, gate_name:, debug:)
      place_tube_in_sorter(item_id: item.id, tube_label: tube_label)
      sort_library(item: item, default_to_sort: default_to_sort, gate_name: gate_name, debug: debug)
    end

    def set_tube(item:, tube_label:, tube_ct:, sort:)
      action = sort ? 'sort' : 'collect data for'
      software_tube_id = set_new_tube(
        action: action,
        tube_label: tube_label,
        tube_ct: tube_ct
      )

      add_software_tube_id(item: item, software_tube_id: software_tube_id)
    end

    def set_new_tube(action: , tube_label:, tube_ct:)
      software_tube_id = TUBE_LABEL_STUB % [tube_ct]

      show do
        title "Set to #{action} #{tube_label}"

        if tube_ct > 1
          check new_tube
          image path_to('new_tube')
        end

        check verify_tube(software_tube_id)
      end

      software_tube_id
    end

    def add_software_tube_id(item:, software_tube_id:)
      sti = item.associations[:software_tube_id]

      if sti.present?
        sti = JSON.parse(sti)
        unless sti.kind_of?(Array)
          raise "Corrupt :software_tube_id (#{sti}) for #{item}"
        end
      else
        sti = []
      end

      sti << software_tube_id
      item.associate(:software_tube_id, sti)
    end

    # TODO: Make this specific to Sony
    def load_tube(item:, tube_label:, sort:)
      show do
        title "Load tube #{tube_label}"

        note "Vortex the tube for 3 Mississippi."
        note "Place the sample tube holder in the sample loader."
        note "If the sample loader door is closed, press the sample
                loader door button to open the sample loader door."

        note "Click <b>Start</b>."
        note "After about 15 seconds, you will begin to see events displayed on the plots."

        if sort
          note "Once a few thousand events have been recorded, click <b>Pause</b>."
        else
          note "Click <b>Record</b>."
          note "Once the instrument finishes recording, click <b>Stop</b>."
        end
      end
    end

    def place_tube_in_sorter(item_id:, tube_label:)
      show do
        title "Prepare collection tube"

        note "Label a collection tube as \"#{item_id} - #{tube_label}.\""
        note "Put 1.0 ml of PBS into the tube."

        note 'Place the holder in the sorter, if it is not already in.'
        image path_to('holder_placement', 'JPG')

        note "Place the labeled tube into the <b>left</b> side of the holder."
        image path_to('place_tube', 'JPG')

        note "Close the door and click <b>Load Collection</b> in the <b>Sort Control</b> pane."
      end
    end

    def sort_library(item:, default_to_sort:, gate_name:, debug:)
      data = show do
        title "Record percentage of positive cells"
        note "Look in the table at the bottom of the data display for the <b>%Total</b> " \
                "in the <b>#{gate_name}</b> gate."
        get "number", var: "pct_positive", label: "Enter the <b>%Total</b>", default: 10
      end

      data[:pct_positive] = [10, 20, 50].sample if debug

      frac_positive = data[:pct_positive] / 100.0

      item.associate(:frac_positive, frac_positive)

      target_events = target_events(default_to_sort: default_to_sort, frac_positive: frac_positive)

      show do
        title "Start sorting"

        note "In the <b>Sort Control</b> panel, set <b>Target Events</b> to " \
                "#{number_with_delimiter(target_events)}"

        note 'Click <b>Sort & Record Start</b> in the <b>Sort Control</b> pane.'
        warning 'Do not open the collection area door during sorting!'

        note "Allow the sorter to run until #{number_with_delimiter(target_events)} " \
                "have been collected in the <b>#{gate_name}</b> gate."

        note "If needed, increase the <b>Sample Pressure</b> until the <b>Event Rate</b> " \
                "is up to <b>6000 eps</b>, keeping the <b>Sort Efficiency</b> greater than 70%."
      end
    end

    def remove_tube_from_sorter(item:, collection_tube:)
      data = show do
            title "Remove tube from sorter"

            note "Once the <b>Target Events</b> has been reached, or the sample is " \
                    "running too low:"
            note "Click <b>Stop</b>."

            separator

            get "number", var: "sort_count", label: "Record the actual <b>Sort Count</b>"

            separator

            note "Remove the #{collection_tube} from the sorter, put the cap back on, " \
                    "and place it on ice."
            image path_to('place_tube', 'JPG')
        end

        data[:sort_count] = [10257, 205982, 501237].sample if debug

        item.associate(:sort_count, data[:sort_count])
    end

    def remove_sample_tube(sample_tube:)
        show do
            title "Remove sample tube"

            note "Click <b>Stop</b>."
            note "Remove the #{sample_tube} from the loader, put the cap back on, " \
                    "and place it on ice."
        end
    end

    def shutdown
      show do
        title "Shutdown"
        note "Ask a lab manager how to shut down this instrument"
      end
    end

    ########## COMMON LANGUAGE ##########

    def new_tube
        "Click  <b>Next tube</b>."
    end

    def verify_tube(software_tube_id)
        "Verify that the tube is labeled <b>#{software_tube_id}</b>"
    end

  end
end