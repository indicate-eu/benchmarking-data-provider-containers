// This file contains general definitions of technical concepts
// that are shared between the different quality indicators.  For
// shared domain (i.e. clinical) definitions, see IndicateQiElements.cql.

library "IndicateQiUtilities" version '1.0.0'

using OMOP version 'v5.4'

include "OMOPHelpers" // for conversions

// This parameter controls the behavior of this library with respect to
// certain runtime errors such as incomplete conversions from OMOP types
// to Quantity as well as failed conversions between physical units.
//
// The following values are supported:
// 'error'    -> abort the evaluation by reporting an error
// 'warning'  -> continue the evaluation with value null and report a warning
// 'continue' -> silently continue the evaluation with value null
parameter OnError String default 'warning'

// Signal conditions

define function SignalProblemWithValue(message String, value Any):
  if message is null then
    Message(null, true, '402', 'Error', 'Internal error: message string is null')
  else
    case
      when OnError = 'error' then
        Message(value, true, '401', 'Error', message)
      when OnError = 'warning' then
        Message(value, true, '401', 'Warning', message)
      else
        value
    end

define function SignalProblem(message String):
  SignalProblemWithValue(message, null)

// Checked conversions to Quantity

define function EnsureQuantity(label       String,
                               value       Decimal,
                               unitConcept OMOP.Concept)
                              returns Quantity:
  case
    when unitConcept is null then
      SignalProblem(label + ' does not have a unit')
    when value is null then
      SignalProblem(label + ' does not have a numeric value')
    else
      Quantity{value: value, unit: unitConcept.conceptCode}
  end

define function EnsureQuantity(label String, measurement Measurement):
  EnsureQuantity(label, measurement.valueAsNumber, measurement.unitConcept)

define function EnsureQuantity(label String, observation Observation):
  EnsureQuantity(label, observation.valueAsNumber, observation.unitConcept)

define function EnsureQuantityWithUnit(label    String,
                                       quantity Quantity,
                                       unit     String)
                                      returns Quantity:
  (1) _
    // Calling ConvertQuantity as a function may be slightly illegal as
    // this possibility is not mentioned in the specification.
    let result: ConvertQuantity(quantity, unit)
      return if result is null then
               SignalProblem('Failed to convert ' + label +
                             + (if quantity.unit is null then
                                  ' without a unit'
                                else
                                  ' with unit ' + quantity.unit)
                             + ' to unit \'' + unit + '\'')
             else
               result

define function EnsureQuantityWithUnit(label       String,
                                       measurement Measurement,
                                       unit        String):
  // TODO(moringenj): include the measurement in the label once we have ToString for Measurement
  (1) _
    let quantity: EnsureQuantity(label, measurement)
      // quantity can be null if OnError is 'warning' or 'continue'
      return if quantity is not null then
               EnsureQuantityWithUnit(label, quantity, unit)
             else
               null

define function EnsureQuantityWithUnit(label       String,
                                       observation Observation,
                                       unit        String):
  // TODO(moringenj): include the observation in the label once we have ToString for Observation
  (1) _
    let quantity: EnsureQuantity(label, observation)
      // quantity can be null if OnError is 'warning' or 'continue'
      return if quantity is not null then
                EnsureQuantityWithUnit(label, quantity, unit)
              else
                null

// Specialized conversions to mol/L

// This function accepts the parameters massPerVolumeUnit and
// molePerVolumeUnit so that the conversionFactor can refer to
// differently scaled input and output units such as mg/dL and mmol/L
// instead of literally g/L and mol/L.
define function "Convert g/L To mol/L"(label             String,
                                       quantity          Quantity,
                                       massPerVolumeUnit String,
                                       molePerVolumeUnit String,
                                       conversionFactor  Decimal):
  (1) _
    let scaled: EnsureQuantityWithUnit(label, quantity, massPerVolumeUnit)
      return Quantity{
        value: conversionFactor * scaled.value,
        unit:  molePerVolumeUnit
      }

define function "EnsureQuantityIn mol/L"(label             String,
                                         quantity          Quantity,
                                         massPerVolumeUnit String,
                                         molePerVolumeUnit String,
                                         massToMoleFactor  Decimal):
  case
    // Check for "mol" substring in the numerator so that other
    // dimensionless units don't get incorrectly treated as mol.
    when Matches(quantity.unit, '.*mol.*/.*')
         and convert quantity to 'mol/L' is not null then
      quantity
    // If the quantity is convertible to g/L, use the conversion
    // factor to convert from massPerVolumeUnit (for example mg/dL) to
    // molePerVolumeUnit (for example mmol/L).
    when convert quantity to 'g/L' is not null then
      "Convert g/L To mol/L"(
        label,
        quantity,
        massPerVolumeUnit,
        molePerVolumeUnit,
        massToMoleFactor
      )
    // For any other units, produce an error so that the issue does
    // not go unnoticed.
    else
      SignalProblem('Unit of ' + label + ' is "' + quantity.unit
                    + '" but must be either convertible to "mol/L" or'
                    + ' convertible to "g/L"')
  end

define function "EnsureQuantityIn mol/L"(label             String,
                                         measurement       Measurement,
                                         massPerVolumeUnit String,
                                         molePerVolumeUnit String,
                                         massToMoleFactor  Decimal):
  (1) _
    let quantity: EnsureQuantity(label, measurement)
      // quantity can be null if OnError is 'warning' or 'continue'
      return if quantity is not null then
               "EnsureQuantityIn mol/L"(
                 label,
                 quantity,
                 massPerVolumeUnit,
                 molePerVolumeUnit,
                 massToMoleFactor
               )
             else
               null

define function "EnsureQuantityIn mol/L"(label             String,
                                         observation       Observation,
                                         massPerVolumeUnit String,
                                         molePerVolumeUnit String,
                                         massToMoleFactor  Decimal):
  (1) _
    let quantity: EnsureQuantity(label, observation)
      // quantity can be null if OnError is 'warning' or 'continue'
      return if quantity is not null then
               "EnsureQuantityIn mol/L"(
                 label,
                 EnsureQuantity(label, observation),
                 massPerVolumeUnit,
                 molePerVolumeUnit,
                 massToMoleFactor
               )
             else
               null
