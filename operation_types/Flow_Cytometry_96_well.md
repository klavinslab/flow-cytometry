# Flow Cytometry 96 well

Protocol for running flow cytometry, including cleaning before and after, and running beads as a calibration sample. Samples are in 96-well plate. Plate can be partially or fully occupied. 
### Inputs


- **96 well plate** [A]  

### Parameters

- **well volume (µL)** 
- **sample type** [E coli,Yeast]
- **require calibration?** [yes, no]



### Precondition <a href='#' id='precondition'>[hide]</a>
```ruby
def precondition(_op)
    
  if _op.input('require calibration?').value == 'yes'
      calibration_operation_type = OperationType.find_by_name("Cytometer Bead Calibration")
      calibration_op = _op.plan.operations.find { |op| op.operation_type_id == calibration_operation_type.id}
      
      if calibration_op.nil?
          _op.associate('Waiting for Calibration','In order to use Cytometer, `Cytometer Bead Calibration` must be run in the same plan')
          return false
      elsif calibration_op.status != 'done'
          _op.associate("Waiting for Calibration","Flow Cytometry cannot begin until Cytometer Calibration completes.")
          return false
      else
          _op.get_association('Waiting for Calibration').delete if _op.get_association('Waiting for Calibration')
          return true
      end
  else
      return true
  end
end
```

### Protocol Code <a href='#' id='protocol'>[hide]</a>
```ruby
# frozen_string_literal: true

needs 'Flow Cytometry/Cytometers'

class Protocol
  include Cytometers

  INPUT_NAME = '96 well plate'
  WELL_VOL = 'well volume (L)' # not really used

  SAMPLE_TYPE = 'sample type'

  def main
    operations.retrieve # should be in loop!!!

    cytometer = Cytometers::BDAccuri.instance

    operations.each do |op|
      show do
        title 'Flow cytometery - info'
        warning "The following should be run on a browser window on the #{cytometer.cytometer_name} computer!"
      end

      cytometer.clean

      cytometer.run_sample_96(sample_string: op.input(SAMPLE_TYPE).val,
                              collection: op.input(INPUT_NAME).collection,
                              operation: op,
                              plan: op.plan)
    end
    cytometer.clean

    # dispose plates
    # operations.each { |op| op.input(INPUT_NAME).item.mark_as_deleted } # Why are we diposing the input collection?
    {}

    #   rescue CytometerInputError => e
    #     show { "Error: #{e.message}" }
  end
end

```
