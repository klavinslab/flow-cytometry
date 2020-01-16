# frozen_string_literal: true

needs 'Standard Libs/AssociationManagement'
needs 'Standard Libs/MatrixTools'
needs 'Standard Libs/Debug'

# Library for flow cytometry.
# Protocols should create an instance of the appropriate cytometer class with
# using the singleton instance method; e.g., `BDAccuri.instance`.
# All methods of the {Cytometer} module are included in these classes.
#
# [Need text on settings]
module Cytometers
  # Module to represent functions on flow cytometers.
  # Individual cytometers should mixin this module and {Singleton}.
  module Cytometer
    include ActionView::Helpers::NumberHelper
    include AssociationManagement
    include MatrixTools
    include Debug

    require 'json'

    KEY_SAMPLE = 'SAMPLE_UPLOAD'
    KEY_BEAD = 'BEAD_UPLOAD'

    FACS_IMAGE_PATH = 'Actions/FACS'

    # Run clean cycle of cytometer.
    def clean(args = {})
      args = clean_defaults.merge(args)
      labels = args[:labels]

      # check that there is sufficient volume of cleaning reagent
      show do
        title 'Check Levels of Cleaning Reagents'
        check "Locate the #{args[:container]}. It should contain #{labels.length} eppendorfs."
        labels.length.times do |ii|
          check "Check that eppendorf labeled  <b>#{labels[ii]}</b> at position  <b>#{args[:position][ii]}</b> contains at least #{args[:min_volume]} mL. If not, add <b>#{args[:add_volume]}</b> mL from jar labeled <b>#{args[:jar_labels][ii]}</b> located in cabinet above cytometer."
        end
      end

      # generate a 'dummy' sample_matrix
      samp_matrix = WellMatrix.create_empty(96, -1)
      samp_matrix.set('D4', 1)
      samp_matrix.set('D5', 1)
      samp_matrix.set('D6', 1)

      # run
      title_string = "Cleaning Template on #{cytometer_name}"
      run_template(template_file: args[:template_file],
                   settings: clean_settings,
                   title_string: title_string,
                   container: args[:container],
                   sample_matrix: samp_matrix)

      # clean-specific message
      show do
        note 'Cytometer does not require supervision during cleaning.'
      end
    end

    # Default arguments for {clean}
    def clean_defaults
      {
        template_file: 'CleanRegular.c6t',
        container: '24 tube rack',
        labels: %w[C D S],
        position: %w[D4 D5 D6],
        jar_labels: %w[Cleaning Decontamination Sheath],
        min_volume: 0.5, # mL
        add_volume: 1 # mL
      }
    end

    # Run bead calibration sample on cytometer from an eppendorf tube.
    # Associates data to item and plan.
    #
    # @param [Hash] args
    # @option args [Item] :bead_stock  stock of calibration beads
    # @option args [Operation] :operation the operation where calibration
    #                 is perfomed
    # @option args [Plan] :plan
    # @option args [Boolean] :reuse_beads  whether or not to use already made diluted beads if there are some leftover
    # @return new sample item representing diluted beads
    def bead_calibration(args)
      args = calibration_defaults.merge(args)
      bead_stock = args[:bead_stock]
      plan = args[:plan]
      op = args[:operation]

      bead_diluted = nil
      if args[:reuse_beads] && check_for_diluted_beads(bead_stock)
        args[:leftovers] = true
        # get most recent beads for this lot no to use as the leftovers. Its fine if this query misses sometimes since
        # diluted bead inventory is informally maintained, and all that really matters is the Lot No.
        bead_diluted = bead_stock.sample.in('Diluted beads').select { |item| item.get('Lot No.') == bead_stock.get('Lot No.') } # this is probably an incredibly slow query. Can we check for the value of data associations in active record queries?
      else
        args[:leftovers] = false
        # create new diluted bead item, same beads as bead stock, in aquarium
        bead_diluted = produce new_sample(bead_stock.sample.name, of: 'Bead', as: 'Diluted beads')
        bead_diluted.associate('Lot No.', bead_stock.get('Lot No.'))
      end

      show_bead_setup(args)

      samp_matrix = WellMatrix.create_empty(96, -1)
      samp_matrix.set('A1', bead_diluted.sample.id)

      # run
      title_string = "Calibration Template on #{cytometer_name}"
      run_template(template_file: args[:template_file],
                   settings: calibration_settings,
                   title_string: title_string,
                   container: args[:container],
                   sample_matrix: samp_matrix,
                   item_number: bead_diluted.id)
      uploads = upload_files(expected_num_uploads: 1)

      [uploads, bead_diluted]
    end

    # Inquire if there is an already made
    # diluted beads available from the target lot
    # that can be used for calibration instead of stock
    #
    # @stock [Item]  the bead stock we were going to use
    def check_for_diluted_beads(stock)
      lotno = stock.get('Lot No.')
      resp = show do
        title 'Check for Existing Diluted Beads'
        note "If there is diluted beads of the right type left over from a previous calibration that aren't too old, then we will use those"
        note 'Diluted beads should be next to where the droplet dispensers are'
        select %w[yes no], label: "Could you find diluted beads from Lot no. #{lotno} that are less than one week old?", var: 'bead_answer', default: 1
        warning 'Do not use beads that are too old or are from a Lot no. other than the one specified'
      end

      (resp.get_response('bead_answer') == 'yes') # return
    end

    # Display instructions for preparing calibration bead sample.
    #
    # @param [Hash] args
    # @option args [Item] bead_stock  the item for the bead stock
    def show_bead_setup(args)
      bead_stock = args[:bead_stock]
      container = args[:container]
      source = "#{args[:bead_volume]} of #{bead_stock.sample.name}"
      destination = "#{args[:media_volume]} of #{args[:media]}"
      show do
        title 'Prepare Calibration sample'
        if !args[:leftovers]
          check "Add #{source}, brown cap to #{destination}"
          check "Add #{source}, white cap to <b>same</b> #{destination}"
        else
          note 'Use leftover diluted beads.'
        end
        check "Place eppendorf containing calibration sample in #{container} at position(s) #{args[:position].join(',')} of #{container}"
      end
    end

    # Default arguments for {bead_calibration}
    def calibration_defaults
      {
        container: '24 tube rack',
        template_file: 'calibration_beads_template.c6t',
        position: ['A1'],
        bead_volume: '1 drop',
        media_volume: '1 mL',
        media: 'PBS',
        reuse_beads: false
      }
    end

    # Run this cytometer on a 96 well plate and associate data.
    #
    # @param [Hash] args
    # @option args [Collection] :collection
    # @option args [Operation] :operation
    # @option args [String] :sample_string
    # @option args [Plan] :plan
    def run_sample_96(args)
      args = run_defaults.merge(args)
      sample_string = args[:sample_string]
      coll = args[:collection]
      plan = args[:plan]
      op = args[:operation]

      if debug # for testing only - ignore this
        matrix = coll.matrix
        matrix[0][0] = 1
        coll.matrix = matrix
        coll.save
      end

      if coll.nil?
        raise CytometerInputError.new, 'collection expected for 96 well plate'
      end

      dimensions = coll.dimensions

      if dimensions.empty?
        raise CytometerInputError.new, 'empty dimensions array for 96 well plate'
      end

      if !(dimensions.all? { |dim| dim > 0 }) || dimensions.length != 2
        raise CytometerInputError.new, 'bad dimensions for 96 well plate'
      end

      # count positions within plate that contain samples
      num_samples = 0
      dimensions[0].times do |rr|
        dimensions[1].times do |cc|
          num_samples += 1 if coll.matrix[rr][cc] > 0
        end
      end

      raise CytometerInputError.new, 'No samples to run' if num_samples < 1

      # convert collection's sample matrix to WellMatrix object for compatibility
      samp_matrix = WellMatrix.from_array(coll.matrix)

      run_template(template_file: args[:templates][sample_string],
                   settings: run_settings[sample_string],
                   title_string: "#{sample_string} measurement",
                   container: args[:container],
                   sample_matrix: samp_matrix,
                   item_number: coll.id)
      uploads = upload_files(expected_num_uploads: 1)

      associate_uploads(KEY_SAMPLE, plan, uploads) # associate each upload individually to plan
      associate_uploads(KEY_SAMPLE, op, uploads) # associate each upload individually to plan
      unless debug
        associate_uploads_to_plate(KEY_SAMPLE.pluralize, coll, uploads)
      end # associate a matrix of uploads to the plate

      uploads
    end

    # Default arguments for {run_sample_96}.
    def run_defaults
      {
        templates: { 'E coli' => 'Ecoli.c6t', 'Yeast' => 'Yeast_gates.c6t' },
        container: '96 well plate: Flat Bottom (Black)'
      }
    end

    # Export FCS files from this cytometer.
    #
    # Associates the {Upload} object for each to the input item and and the list
    # of objects to the plan of the operation.
    #
    # @param [Hash] args
    # @option args [Fixnum] :expected_num_uploads  the number of expected files
    #                 (default: 1)
    # @return [Array<Upload>] the array of uploads for exported files
    private def upload_files(args)
      args = upload_defaults.merge(args)
      expected_num_uploads = args[:expected_num_uploads]
      dirname = export_and_select_directory
      gather_uploads(expected_num_uploads, dirname)
    end

    # Defines the default values for arguments to {upload_files}
    #
    # @return [Hash] the default argument values
    private def upload_defaults
      { expected_num_uploads: 1 }
    end

    # Upload and check that have expected number of files
    # Give user 3 attempts to get all files. Return an Array of upload objects.
    # @param [Integer] expected_num_uploads  the number of expected files
    # @param [String]  dirname  the name of the directory where the files reside
    # @return [Array<Upload>]  an array of uploads for the exported files, or nil if nothing was uploaded
    private def gather_uploads(expected_num_uploads, dirname)
      uploads_from_show = {}
      num_uploads = 0
      attempt = 0; # number of upload attempts
      while (attempt < 3) && (num_uploads < expected_num_uploads)
        attempt += 1
        if attempt > 1
          show { warning 'Number of uploaded files was incorrect, please try again!' }
        end
        uploads_from_show = show do
          title "Select and highlight all .fcs files in directory <b>Desktop/FCS Exports/#{dirname}</b>"
          upload var: 'fcs_files'
        end

        unless uploads_from_show[:fcs_files].nil?
          num_uploads = uploads_from_show[:fcs_files].length
        end
      end
      uploads_from_show_to_array(uploads_from_show, :fcs_files)
    end

    # Converts the output of a show block that recieves uploads into a
    # list of uploads.
    #
    # @param [Hash] uploads_from_show  the hash return by a show block which accepts user input
    # @param [Symbol] upload_var  the symbol key which the target uploads are stored under in uploads_from_show
    # @return [Array<Upload>]  an array of uploads contained in the uploads_From_show at the given key
    private def uploads_from_show_to_array(uploads_from_show, upload_var)
      return spoof_uploads if debug

      upload_list = []
      if uploads_from_show[upload_var].nil?
        return upload_list
      else
        uploads_from_show[upload_var].each_with_index do |upload_hash, _ii|
          up = Upload.find(upload_hash[:id])
          upload_list.push(up)
          # upload_list[ii] = up
        end
      end

      upload_list
    end

    # Ignore, this is for debugging only
    private def spoof_uploads
      [Upload.find(1), Upload.find(2)]
    end

    # Associate all `uploads` to the `target` DataAssociator. The keys of each upload will be
    # the concatenation of `key_name` and that upload's id.
    # Associating fcs files to the plan and operation makes fcs data of any specific well
    # easily accessible to users
    #
    # @param [String] key_name  the name which describes this upload set
    # @param [Plan] plan  the plan that the uploads will be associated to
    # @param [Array<Upload>] uploads  An Array containing several Uploads
    # @effects  associates all the given uploads to `plan`, each with a
    #         unique key generated from the combining `keyname` and upload id
    def associate_uploads(key_name, target, uploads)
      if target
        associations = AssociationMap.new(target)
        uploads.each do |up|
          associations.put("U#{up.id}_#{key_name}", up)
        end
        associations.save
      end
    end

    # Associate a matrix containing all `uploads` to `collection`.
    # The upload matrix will map exactly to the sample matrix of
    # `collection`, and it will be associated to `collection` as a value
    # of `key_name`
    #
    # @param [String] key_name  the key that the upload matrix will
    #           be associated under
    # @param [Collection] collection  what the upload matrix will be
    #           associated to
    # @param [Array<Upload>] uploads  An Array containing several Uploads
    # @effects  associates all the given uploads to `collection` as a 2D array inside a singleton hash
    private def associate_uploads_to_plate(key_name, coll, uploads)
      # figure out size of collection (24 or 96)
      dims = coll.dimensions
      size = dims[0] * dims[1]
      well_uploads = WellMatrix.create_empty(size, -1)
      uploads.each do |up|
        # the first 3 letters of the upload filename will be the
        # alphanumeric well coordinate
        alpha_coord = up.name[0..2]
        well_uploads.set(alpha_coord, up.id)
      end
      coll_associations = AssociationMap.new(coll)
      # ensure we aren't overwriting an existing association
      unless coll_associations.get(key_name).nil?
        i = 0
        i += 1 until coll_associations.get("#{key_name}_#{i}").nil?
        key_name = "#{key_name}_#{i}"
      end

      coll_associations.put(key_name, 'upload_matrix' => well_uploads.to_a)
      coll_associations.save
    end

    def associate_uploads_to_bead_item(key_name, bead_item, uploads)
      bead_item_associations = AssociationMap.new(bead_item)
      unless bead_item_associations.get(key_name).nil?
        i = 0
        i += 1 until bead_item_associations.get("#{key_name}_#{i}").nil?
        key_name = "#{key_name}_#{i}"
      end
      bead_item_associations.put(key_name, uploads.first)
      bead_item_associations.save
    end

    # Display instructions for setting up a template and running it.
    #
    # @param [Hash] args
    # @option args [String] :template_file  the name of the template file
    # @option args [Hash] :settings  the hash of the settings for this run
    # @option args [String] :title_string  the title for the show
    # @option args [String] :container  previously known as "holder"
    # @option args [WellMatrix] :sample_matrix  an 8x12 WellMatrix with sample IDs for
    #                 occupied wells, -1 otherwise
    # @option args [Fixnum] :item_number  the item.id used in naming .c6 file
    # @raises CytometerInputError if the provided sample_matrix is nil
    def run_template(args)
      args = template_defaults.merge(args)
      template_file = args[:template_file]
      title_string = args[:title_string]
      container = args[:container]
      samp_matrix = args[:sample_matrix]

      raise CytometerInputError.new, 'sample_matrix is nil' if samp_matrix.nil?

      # build string, .c6 filename
      item_string = args[:item_number]
      item_string = "_#{item_string}_" unless item_string.nil?
      c6_filename = File.basename(template_file, '.c6t') +
                    item_string +
                    Time.zone.now.to_date.to_s +
                    '.c6'

      # visually check culture positions
      show do
        title "Check new sample #{title_string}"
        note 'Only the shaded positions should contain samples:'
        table samp_matrix.display_position_table { |samp| samp > 0 } # highlight cells with sample id > 0
      end

      choose_template(title_string, template_file, container)
      load_samples(title_string, container)
      enter_settings(title_string, args[:settings])
      start_run(title_string, samp_matrix, c6_filename)
    end

    ### FACS methods

    def template_defaults
      { item_number: '' }
    end

    def target_events(default_to_sort:, frac_positive:)
      (default_to_sort * frac_positive).to_i
    end

    def required_sample_tube; end

    def check_sweet_spot; end

    # Error class for bad cytometer parameters.
    class CytometerInputError < StandardError; end
  end

  # Singleton class for the BDAccuri cytometer.
  # The interface of this class is defined by a mixin of the {Cytometer} module,
  # which provides the main interface for interacting with the cytometer.
  class BDAccuri
    include Singleton
    include Cytometer

    CYTOMETER_NAME = 'BD Accuri'
    TEMPLATE_DIR = 'aq_templates'

    # Gets Cytometer name. Otherwise it would be unavailable in 'parent' module.
    def cytometer_name
      CYTOMETER_NAME
    end

    # The settings used for calibration beads with this cytometer.
    def calibration_settings
      {
        settings: {
          'Run Limits' => '30 L',
          'Fluidics' => 'Slow',
          'Set Threshold' => 'FSC-H less than 300,000, SSC-H less than 250,000',
          'Wash Settings' => 'None',
          'Agitate Plate' => 'None'
        }
      }
    end

    # The settings used for cleaning this cytometer.
    def clean_settings
      {
        settings: {
          'Run Limits' => '2 Min',
          'Fluidics' => 'Slow',
          'Set Threshold' => 'FSC-H less than 80,000',
          'Wash Settings' => 'None',
          'Agitate Plate' => 'None'
        }
      }
    end

    # The settings for running this cytometer by organism.
    def run_settings
      {
        settings: {
          'E coli' => { 'Run Limits' => '60,000 events, 1 Min, 50 L',
                        'Fluidics' => 'Medium',
                        'Set Threshold' => 'FSC-H less than 8,000',
                        'Wash Settings' => 'None',
                        'Agitate Plate' => '1 Cycle every 12th well' },
          'Yeast' => { 'Run Limits' => '30,000 events',
                       'Fluidics' => 'Fast',
                       'Set Threshold' => 'FSC-H less than 400,000',
                       'Wash Settings' => 'None',
                       'Agitate Plate' => '1 Cycle every 12th well' }
        }
      }
    end

    # Display instructions for exporting FCS files and selecting the directory.
    #
    # @return [String] the name of the directory containing the exported files
    private def export_and_select_directory
      show do
        title "Export Data from Flow Cytometer #{CYTOMETER_NAME}"
        check 'Make sure that flow cytometer run is <b>DONE!</b>'
        check 'Press <b>CLOSE RUN DISPLAY</b>'
        check 'Select <b>File</b> => <b>Export ALL Samples as FCS...</b> (see below)'
        image 'Actions/FlowCytometry/saveFCS_menu_cropped.png'
      end
      ui = show do
        title "Select Data Directory for Flow Cytometer #{CYTOMETER_NAME}"
        warning 'Look for the name of the FCS directory that is created, as in example below. Your directory name will be different!'
        image 'Actions/FlowCytometry/saveFCS_dirname_cropped.png'
        get 'text', var: 'dirname', label: 'Enter the name of the export directory in <b>Desktop/FCS Exports/</b>'
      end
      ui[:dirname]
    end

    # Displays instructions for selecting the template file for the container type.
    #
    # @param [String] title_string  the title for the page
    # @param [String] template_file  the name of the template file
    # @param [String] container  the container type
    def choose_template(title_string, template_file, container)
      show do
        title "Select #{title_string}"
        check 'Open the BD Accuri software BD CSampler if not already open'
        check 'If the program is open and displaying <b>DONE!</b>, press <b>CLOSE RUN DISPLAY</b>'
        check 'Go to <b>File</b> => Select <b>Open workspace or template</b>'
        warning 'Do not save changes to workspace'
        check "Under <b>#{TEMPLATE_DIR}</b>, find and open <b>#{template_file}</b>"
        warning 'The filename should end in <b>.c6t</b>!'
        check "Make sure the <b>Plate Type</b> is <b>#{container}</b>"
      end
    end

    # Displays instructions for loading samples in the cytometer.
    #
    # @param [String] title_string  the title for the page
    # @param [String] container  the container type
    def load_samples(title_string, container)
      # load samples
      show do
        title "Load sample #{title_string}"
        warning 'Beware of moving parts! Keep black tray beneath cytometer free!'
        check 'Press <b>Eject Plate</b>'
        check 'Remove the plate from the cytometer arm and place it on cytometer lid'
        check "For <b>#{container}</b> containing <b>#{title_string}</b>: remove all seals or lids, uncap any capped samples"
        check "Place <b>#{container}</b> containing <b>#{title_string}</b> on cytometer arm"
        warning 'Make sure well <b>A1</b> is aligned with the red sticker on the cytometer arm!'
        check 'Press <b>Load Plate</b>'
      end
    end

    # Displays instructions for loading settings to the cytometer.
    #
    # @param [String] title_string  the title for the page
    # @param [Hash] settings  the settings for the cytometer
    # @see calibration_settings
    # @see clean_settings
    # @see run_settings
    def enter_settings(title_string, settings)
      show do
        title "Settings for #{title_string}"
        check 'Select the <b>Auto Collect</b> table towards the top of the window'
        note 'You will be using the settings listed below'
        warning 'You may enter settings manually, <b>OR</b> press Control+left mouse button click to select a well that already has these settings'
        warning 'A red box will appear around the selected well'
        settings&.each do |key, value|
          check "Make sure that <b>#{key}</b> is set to:"
          value.each { |type, val| bullet "#{type} - #{val}" }
        end
      end
    end

    # Displays instructions to start the cytometer run.
    #
    # @param [String] title_string  the title for the page
    # @param [WellMatrix] sample_matrix  the matrix indicating where samples occur
    # @param [String] c6_filename  the name for the workspace file
    def start_run(title_string, samp_matrix, c6_filename)
      # run
      show do
        title "Select wells and run #{title_string}"
        check 'On the BD Accuri, using the left mouse button (or the Select/Deselect All links), click on all plate positions to be measured:'
        table samp_matrix.display_position_table { |samp| samp > 0 } # highlight cells with sample id > 0
        warning 'Only the well(s) that are listed in the Aquarium table should be checked'
        check 'Click <b>Apply Settings</b> to apply the seetings to all checked wells. You will be prompted to save the workspace'
        check "Save file as <b>#{c6_filename}</b>"
        check 'Click <b>OPEN RUN DISPLAY</b>'
        check 'Click <b>AUTORUN</b>'
      end
    end
  end
end
