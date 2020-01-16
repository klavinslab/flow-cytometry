# frozen_string_literal: true

needs 'Flow Cytometry/Cytometers'

module Cytometers
  # Module for the BD Aria III cytometer.
  module BDAriaIII
    include Cytometer

    CYTOMETER_NAME = 'BD Aria III'
    TEMPLATE_DIR = ''

    # TODO: handle secrets differently
    LOGIN_USER = 'dummy_user'
    LOGIN_PASSWORD = 'dummy_password'

    TUBE_LABEL_STUB = 'Tube_%03d'

    DEFAULT_LOCATION = 'Health Sciences Building room H-581'

    def cytometer_name
      CYTOMETER_NAME
    end

    def location
      DEFAULT_LOCATION
    end

    def image_path
      FACS_IMAGE_PATH
    end

    def path_to(filename, extension = 'png')
      "#{image_path}/#{filename}.#{extension}"
    end

    def required_sample_tube
      '5 ml polystyrene round-bottom tube (Falcon 352054)'
    end

    def go_to_facs_and_login
      show do
        title 'Go to the FACS'
        note 'Take the cooler and the box with you.'
        note "The FACS is in #{location}."
      end

      show do
        title 'Log into the FACS instrument'

        note "User: #{LOGIN_USER}"
        note "Password: #{LOGIN_PASSWORD}"
      end
    end

    def set_up_instrument(experiment_name:, template:, events_to_record:, target_events:, args: {})
      check_sweet_spot

      create_new_experiment(
        name: experiment_name,
        template: template
      )

      verify_settings(
        events_to_record: events_to_record
      )

      set_up_sorting(
        target_events: target_events
      )
    end

    def check_sweet_spot
      show do
        title 'Check the Sweet Spot'

        check 'Make sure the Sweet Spot is engaged.'
        image path_to('sweetspot')
        note 'The purple and yellow shapes should be touching as in the figure.'
      end
    end

    def create_new_experiment(name:, template:)
      show do
        title 'Load the experiment template'

        note 'In the menu bar, click on <b>Experiment</b>, then <b>New Experiment</b>.'
        image path_to('new_experiment')

        note "In the <b>Experiment Templates</b> window, select <span style=\"background-color:yellow\"><b>#{template}</b></span>."
        image path_to('select_template')
      end

      show do
        title 'Open and rename the experiment'

        note 'Double click on the notebook so that it opens up.'
        image path_to('open_workbook')

        note "Rename the experiment as <span style=\"background-color:yellow\"><b>#{name}</b></span>."
        image path_to('rename')
      end
    end

    def verify_settings(events_to_record:)
      show do
        title 'Verify settings'

        note 'Verify that the <b>Stopping Gate</b> is set to <b>All Events</b>.'
        note "Verify that <b>Events To Record</b> is set to <b>#{number_with_delimiter(events_to_record)}</b>."
      end
    end

    def set_up_sorting(target_events:)
      show do
        title 'Set up sorting'

        note 'Click the <b>+</b> next to <b>Global Worksheets</B>, then the one next to <b>Global Sheet1</b>, then <b>Sort Layout</b>.'

        note 'Select or verify the following settings:'
        check '<b>Device:</b> 2 Tube'
        check '<b>Precision:</b> Purity'
        check "<b>Target Events:</b> #{number_with_delimiter(target_events)}"
        check '<b>Save Sort Reports:</b> Save All'

        note 'Check that the settings match this image, except <b>Target Events</b> and the number next to <b>P1</b>.'
        image path_to('sort_setup_complete')
      end
    end

    def set_and_run_tube(item:, tube_label:, tube_ct:, sort:)
      set_tube(item: item, tube_label: tube_label, tube_ct: tube_ct, sort: sort)
      load_tube(item: item, tube_label: tube_label)
    end

    def sort_tube(item:, tube_label:, default_to_sort:, gate_name: nil, debug:)
      place_tube_in_sorter(item_id: item.id, tube_label: tube_label)
      sort_library(item: item, default_to_sort: default_to_sort, debug: debug)
    end

    def set_tube(item:, tube_label:, tube_ct:, sort:)
      action = sort ? 'sort' : 'collect data for'

      software_tube_id = item.associations[:software_tube_id]

      if software_tube_id
        set_existing_tube(action, tube_label, software_tube_id)
      else
        software_tube_id = set_new_tube(
          action: action,
          tube_label: tube_label,
          tube_ct: tube_ct
        )
        item.associate(:software_tube_id, software_tube_id)
      end
    end

    def set_existing_tube(action, tube_label, software_tube_id)
      show do
        title "Set to #{action} #{tube_label}"

        check click_green_arrow(software_tube_id)
        image path_to('green_arrow')
      end
    end

    def set_new_tube(action:, tube_label:, tube_ct:)
      software_tube_id = format(TUBE_LABEL_STUB, tube_ct)

      show do
        title "Set to #{action} #{tube_label}"

        if tube_ct > 1
          check new_tube
          image path_to('new_tube')
        end

        check verify_tube(software_tube_id)

        check click_green_arrow(software_tube_id)
        image path_to('green_arrow')
      end

      software_tube_id
    end

    def place_tube_in_sorter(item_id:, tube_label:)
      show do
        title 'Prepare collection tube'

        note "Label a collection tube as \"#{item_id} - #{tube_label}.\""
        note 'Put 1 ml of PBS into the tube.'

        note 'Place the labeled tube into the left side of the holder like this.'
        image path_to('place_tube', 'JPG')

        note 'Insert the holder into the sorter and push it back as far as it will go.'
        image path_to('holder_placement', 'JPG')
      end
    end

    def load_tube(item:, tube_label:)
      show do
        title "Load tube #{tube_label}"

        note 'Vortex the tube for 3 Mississippi.'
        note 'Load the tube onto the stand and close the door.'
        # image path_to('sample_tube')

        note 'Click <b>Load</b> in the Acquisition Dashboard.'
        note 'After about 15 seconds, you will begin to see events displayed in the analysis sheet.'

        unless item.associations[:data_collected]
          check 'Click <b>Record Data</b>.'
          end
      end
    end

    def sort_library(item:, default_to_sort:, debug:)
      data = show do
        title 'Record percentage of positive cells'

        note 'Look in the table at the bottom of the data display for the <b>%Total</b> in the <b>P1</b> gate.'
        get 'number', var: 'pct_positive', label: 'Enter the <b>%Total</b>', default: 10
      end

      data[:pct_positive] = [10, 20, 50].sample if debug

      frac_positive = data[:pct_positive] / 100.0

      item.associate(:frac_positive, frac_positive)

      target_events = target_events(default_to_sort: default_to_sort, frac_positive: frac_positive)

      show do
        title 'Start sorting'

        note 'In the <b>Sort Layout</b> window:'
        note "1. Set <b>Target Events</b> to #{number_with_delimiter(target_events)}"
        note '2. Right click on the <b>P1</b> field (under <b>Left</b>) and select <b>Remove</b>'
        note '3. Right click on the same field and <b>add P1</b>'
        note 'Click <b>Sort</b>'
        note 'Adjust the flow rate as needed, up to <b>8.0</b>, keeping the efficiency <b>> 90%</b>'
        note "Allow the sorter to run until #{number_with_delimiter(target_events)} have been collected in the <b>P1</b> gate."
      end
    end

    def remove_tube_from_sorter(collection_tube:, item: nil)
      show do
        title 'Remove tube from sorter'

        note 'Once the <b>Target Events</b> has been reached, or the sample is running too low:'
        note 'Click <b>Stop Sorting</b>.'
        note "Remove the #{collection_tube} from the sorter, put the cap back on, and place it on ice."
        image path_to('place_tube', 'JPG')
      end
    end

    def remove_sample_tube(sample_tube:)
      show do
        title 'Remove sample tube'

        note 'Click <b>Unload</b>.'
        note "Remove the #{sample_tube} from the platform, put the cap back on, and place it on ice."
      end
    end

    def shutdown
      show do
        title 'Copy the sort reports to our data folder'

        note 'Open two new Explorer windows'
        note 'In one window, navigate to the <b>sort reports folder (D:\\BD\\FACSDiva\\SortReports)</b>'
        note 'Sort the files by <b>Date modified</b>'
        note "In the other window, navigate to <b>our data folder (D:\\AriaData\\#{LOGIN_USER}\\SortReports)</b>"
        note '<b>COPY</b> the most recently-modified folder in the <b>sort reports folder</b> to <b>our data folder</b>'
        image path_to('sort_reports')
      end
      show do
        title 'Disengage the Sweet Spot'

        check 'Click once on the purple and yellow shapes to turn the Sweet Spot OFF.'
        image path_to('sweetspot')
      end

      show do
        title 'Shutdown the instrument'

        note 'Logout of the software'
        note 'Log back in as <b>User:</b> ShutdownDaily'
        note 'Run shutdown: 10 min bleach and 4 min water.'
      end
    end

    ########## COMMON LANGUAGE ##########

    def new_tube
      'Click  <b>Next tube</b>.'
    end

    def verify_tube(software_tube_id)
      "Verify that the #{@tube_ct > 1 ? 'new' : 'first'} tube is labeled <b>\"#{software_tube_id}\"</b>"
    end

    def click_green_arrow(software_tube_id)
      "Click on the arrow next to <b>\"#{software_tube_id}\"</b>  and make sure it is <b><span style=\"color: green\">GREEN</span></b>"
    end
  end
end
