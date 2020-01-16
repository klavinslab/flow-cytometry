# Cytometer Bead Calibration

For most plan which runs **Flow Cytometry** operation, a **Cytometer Calibration** operation is required to be in the **plan**. 

*Flow Cytometery operations in a plan will not run until the calibration is run, if they are set up to require calibration.*

**In most cases only one calibration should be done per plan**
### Inputs


- **calibration beads** [B]  





### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(_op)
  true
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# frozen_string_literal: true

# Instructions to Calibrate cytometer, calibration measurements are retrieved and
# cytometer is prepared for flow.
#
# if operations are batched and use the same bead type,
# then we only calibrate once and assign the measurement
# results from that calibration to all operations in that bead type group
#
needs 'Flow Cytometry/Cytometers'
needs 'Standard Libs/Debug'
class Protocol
  include Cytometers
  include Debug

  BEAD_STOCK = 'calibration beads'
  KEY_BEAD = 'BEAD_UPLOAD'

  def intro
    show do
      title 'Calibrating the Flow Cytometer'
      separator
      note 'To compare different experiments against each other we must have a way to compare the fluorescence intensities across different flow cytometers.'
      note 'To achieve this we will be using small beads that fluoresce multiple colors.'
      note '<b>1.</b> Take chosen beads and dilute, if necessary.'
      note '<b>2.</b> Setup flow cytometer workspace and measure bead sample.'
      note '<b>3.</b> Upload .fcs file to Aquarium.'
    end
  end

  def main
    cytometer = Cytometers::BDAccuri.instance
    intro
    op_groups_by_bead = operations.group_by { |op| op.input(BEAD_STOCK).item }
    take_beads(op_groups_by_bead: op_groups_by_bead)
    op_groups_by_bead.each do |bead, ops|
      cytometer.clean
      # perform a calibration
      uploads, diluted_bead_item = cytometer.bead_calibration(bead_stock: bead, reuse_beads: true)
      cytometer.associate_uploads_to_bead_item('BEADS_uploads', bead, uploads)
      cytometer.associate_uploads_to_bead_item('BEADS_uploads', diluted_bead_item, uploads)

      cytometer.associate_uploads(KEY_BEAD, diluted_bead_item, uploads)

      # associate calibration measurments. If measurements already exist in this plan then dont overwrite
      ops.each do |op|
        # Add the diluted beads to the operations FieldValues
        # fv_name = 'Measured Diluted Beads'
        # op.add_input fv_name, diluted_bead_item.sample, diluted_bead_item.object_type
        # op.input(fv_name).set item: diluted_bead_item
        cytometer.associate_uploads(KEY_BEAD, op, uploads)
        safe_key = KEY_BEAD; i = 1
        until op.plan.get(safe_key).nil?
          safe_key = KEY_BEAD + i.to_s
          i += 1
        end
        cytometer.associate_uploads(KEY_BEAD, op.plan, uploads)
      end
    end
    cytometer.clean

    return_beads op_groups_by_bead, cytometer
    {}
  end

  # Create hashmap from bead sample to list of operations that
  # use that bead item
  def group_operations_by_bead
    ops_by_bead = {}
    operations.each do |op|
      bead_stock = op.input(BEAD_STOCK).item
      ops_by_bead[bead_stock] = [] if ops_by_bead[bead_stock].nil?
      ops_by_bead[bead_stock] << op
    end
    ops_by_bead
  end

  def take_beads(op_groups_by_bead:)
    show do
      title 'Collect Calibration Beads'
      note 'In the next step retrieve the following calibration beads:'
      op_groups_by_bead.each do |bead, _ops|
        bullet "Grab #{bead.sample.name} #{bead} Bead dispensers from Lot #{bead.get('Lot No.')}"
      end
      note 'If a valid leftover eppendorf of diluted beads exists for the given Lot, grab that instead'
      note 'Make sure to pay attention to Lot No. of beads throughout this protocol.'
    end
    take op_groups_by_bead.keys, interactive: true
  end

  def return_beads(op_groups_by_bead, _cytometer)
    show do
      title 'Return Calibration Beads'
      note 'Return beads to the correct Lot'
      op_groups_by_bead.each do |bead, _ops|
        check "Return bead dispensers and diluted beads to #{bead.get('Lot No.')}"
      end
    end
    release op_groups_by_bead.keys, interactive: true
  end
end

```
