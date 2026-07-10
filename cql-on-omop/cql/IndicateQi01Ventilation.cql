// Name     01 - Ventilation
// Version  1.0
//
// Description:
//   Lung-protective mechanical ventilation should reduce inflammation and lung
//   damage. Therefore patients with ARDS should be ventilated with a tidal
//   volume around 6 mL/kg ideal body weight (IBW).  The positive end
//   expiratory pressure (PEEP) should be adjusted according to the ARDSnet
//   PEEP table (mild ARDS: low PEEP table, moderate/severe ARDS: high PEEP
//   table).  The plateau pressure should be lower or equal 30 cmH2O.  The
//   inspiratory pressure difference (driving pressure, Pdelta) should be
//   lower or equal 14 cmH2O.

library "IndicateQi01Ventilation" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers

include TimePeriods called T

include IndicateQiUtilities called U
include IndicateQiElements called elm

include VentilationProcedures
include TidalVolumeMeasurements

code "ARDS Condition": '4195694' from elm.OMOPSV // ICD10 based code: '45552897'

code "Invasive Ventilation Procedure": '37158404' from elm.OMOPSV

concept "Ventilation Procedure": {
  "Invasive Ventilation Procedure"
}

code "Horowitz index in Arterial blood":                                         '3029943' from elm.OMOPSV
code "Horowitz index adjusted to patients actual temperature in Arterial blood": '3029268' from elm.OMOPSV
concept "PaO2/FiO2 (Horowitz index) Measurement": {
  "Horowitz index in Arterial blood",
  "Horowitz index adjusted to patients actual temperature in Arterial blood"
}

code "PaO2 Default Measurement":              '3027801' from elm.OMOPSV
code "PaO2 Temperature Adjusted Measurement": '3022803' from elm.OMOPSV

concept "PaO2 Measurement": {
  "PaO2 Default Measurement",
  "PaO2 Temperature Adjusted Measurement"
}

code "Inspired oxygen concentration":                                         '4353936' from elm.OMOPSV
code "Oxygen/Inspired gas Respiratory system --on ventilator":                '3026238' from elm.OMOPSV
code "Oxygen/Inspired gas Respiratory system by O2 Analyzer --on ventilator": '3025408' from elm.OMOPSV
code "Oxygen/Total gas setting [Volume Fraction] Ventilator":                 '3024882' from elm.OMOPSV

concept "FiO2 Measurement": {
  "Inspired oxygen concentration",
  "Oxygen/Inspired gas Respiratory system --on ventilator",
  "Oxygen/Inspired gas Respiratory system by O2 Analyzer --on ventilator",
  "Oxygen/Total gas setting [Volume Fraction] Ventilator"
}

code "PEEP Total, Measured Measurement": '42527140' from elm.OMOPSV
code "PEEP Setting Measurement":         '4216746'  from elm.OMOPSV
code "PEEP General Measurement":         '4353713'  from elm.OMOPSV

concept "PEEP Measurement": {
  "PEEP Total, Measured Measurement",
  "PEEP Setting Measurement",
  "PEEP General Measurement"
}

code "Plateau Pressure Measurement": '44782825' from elm.OMOPSV

// Unit: usually cmH2O but may be some other pressure unit.  Converted to
// cm[H2O] in "Peak Inspiratory Pressure Measurements".
code "Inspiratory Pressure Setting": '4215838' from elm.OMOPSV

// Unit: usually mmHg (different for CAVE).  Has to be converted to
// unit cmH2O. Converted to cm[H2O] in "Peak Inspiratory Pressure
// Measurements".
code "Peak Inspiratory Pressure Measurement": '4101694' from elm.OMOPSV

// PEEP Tables

define function "Low PEEP for FiO2"(FiO2 Quantity):
  Quantity{
    value: case
             when FiO2 < 0.5 '%' then 5
             when FiO2 < 0.6 '%' then 8
             when FiO2 < 0.8 '%' then 10
             when FiO2 < 1.0 '%' then 14
             else 18
           end,
    unit:  'cm[H2O]'
  }

define function "High PEEP for FiO2"(FiO2 Quantity):
  Quantity{
    value: case
             when FiO2 < 0.4 '%' then 5
             when FiO2 < 0.5 '%' then 14
             when FiO2 < 0.6 '%' then 16
             when FiO2 < 0.9 '%' then 20
             else 22
           end,
    unit:  'cm[H2O]'
  }

context Patient

// Sorted in reverse chronological order for "Last Observation Carried
// Forward" (LOCF) logic below.
define "PaO2 Measurements":
  [Measurement: "PaO2 Measurement"] m
    return all m
    sort by measurementDatetime desc

define "FiO2 Measurements":
  [Measurement: "FiO2 Measurement"] m
    return all m
    sort by measurementDatetime desc

define "PaO2/FiO2 (Horowitz index) Measurements":
  [Measurement: "PaO2/FiO2 (Horowitz index) Measurement"] m
    return all m
    sort by measurementDatetime desc

// This is not sorted like the other measurements because the PEEP
// measurements dictate the timing and the other measurements are carried
// forward to align with the PEEP measurements.
define "PEEP Measurements":
  [Measurement: "PEEP Measurement"] m
    return all m
    sort by measurementDatetime

define "Plateau Pressure Measurements":
  [Measurement: "Plateau Pressure Measurement"] m
    return all m
    sort by measurementDatetime desc

// Merge data from the measurement and observation domains by
// converting to Quantity.  Sort in descending order for LOCF logic.
// Convert to cm[H2O].
define "Peak Inspiratory Pressure Measurements":
  (Flatten({
     ([Measurement: "Peak Inspiratory Pressure Measurement"] m
        return all {
          datetime: convert m to DateTime,
          // TODO(moringenj): use an error-checking conversion
          quantity: convert (convert m to Quantity) to 'cm[H2O]'
        }
     ),
     ([Observation: "Inspiratory Pressure Setting"] o
        return all {
          datetime: convert o to DateTime,
          // TODO(moringenj): use an error-checking conversion
          quantity: convert (convert o to Quantity) to 'cm[H2O]'
        }
     )
   })) q
    return all q
    sort by datetime desc

define "Ventilation Procedures":
  [ProcedureOccurrence: VentilationProcedures."PCV or VCV Ventilation Procedure"]

define "Intubation Tube Exposures":
  [DeviceExposure: elm."Intubation Tube"]

define "ARDS Conditions":
  [ConditionOccurrence: "ARDS Condition"]

// In CQL
//
//   @2026-06-17T10:11:12 same or before @2026-06-17T10:11:12 => true
//   @2026-06-17T10:11:13 same or before @2026-06-17T10:11:12 => false
//
// but
//
//   @2026-06-17T10:11 same or before @2026-06-17T10:11:12 => null
//
// In this use case, we want the third example to evaluate to true.  For
// greater precision mismatches, we want false.
define function "Same or Before with Minute Precision"(earlier DateTime,
                                                       later   DateTime):
  (1) _
    let fullPrecisionResult:   earlier same or before later,
        minutePrecisionResult: earlier same minute or before later
      return case
               when fullPrecisionResult is not null then
                 fullPrecisionResult
               when minutePrecisionResult is not null then
                 minutePrecisionResult
               else
                 false
             end

// Last Observation Carried Forward
define function "PaO2 LOCF"(targetTime DateTime):
  First("PaO2 Measurements" m
          where "Same or Before with Minute Precision"(
                  convert m to DateTime,
                  targetTime
                )
          return all m)

define function "FiO2 LOCF"(targetTime DateTime):
  First("FiO2 Measurements" m
          where "Same or Before with Minute Precision"(
                  convert m to DateTime,
                  targetTime
                )
          return all m)

define function "PaO2/FiO2 LOCF"(targetTime DateTime):
  First("PaO2/FiO2 (Horowitz index) Measurements" m
          where "Same or Before with Minute Precision"(
                  convert m to DateTime,
                  targetTime
                )
          return all m)

define function "Plateau Pressure Measurement LOCF"(targetTime DateTime):
  First("Plateau Pressure Measurements" m
          where "Same or Before with Minute Precision"(
                  convert m to DateTime,
                  targetTime
                )
          return all m)

define function "Peak Inspiratory Pressure LOCF"(targetTime DateTime):
  First("Peak Inspiratory Pressure Measurements" m
          where "Same or Before with Minute Precision"(m.datetime, targetTime)
          return all m.quantity)

define function "Ventilation Mode"(targetTime DateTime):
  (1) _
    let procedure: First("Ventilation Procedures" p
                           where targetTime during (convert p to Interval<DateTime>)
                           return all p)
      return case
               when procedure.procedureConcept ~ VentilationProcedures."Pressure Driven Ventilation Procedure"
                 then 'Pressure Driven'
               when procedure.procedureConcept ~ VentilationProcedures."Volume Driven Ventilation Procedure"
                 then 'Volume Driven'
               else
                 null
             end

define "Usable Tidal Volume Measurements":
  // Select Tidal Volume measurements according to the "Tidal volume (Vt)"
  // (322) concept set. All concept in that concept use the unit mL for the
  // measurements.  We Do not retrieve measurements according to the "Tidal
  // volume per body weight (Vt/kg)" concept set since such measurements are
  // uncommon and would require scaling with the (actual) body weight.
  [Measurement: TidalVolumeMeasurements."Tidal Volume Measurements"] m
    // TODO(moringenj): include the measurement in the message once we have ToString for Measurement
    where U.EnsureQuantityWithUnit('Tidal volume measurement', m, 'mL') is not null
    return all m
    sort by measurementDatetime desc

define function "Tidal Volume LOCF"(targetTime DateTime):
  First(("Usable Tidal Volume Measurements") m
          where m same hour or before targetTime
          return all m)

// PaO2 unit mm[Hg], FiO2 unit %.  This function produces mm[Hg].
define function "Ensure PaO2/FiO2"(peepTime DateTime):
  (1) _
    let "PaO2/fiO2": "PaO2/FiO2 LOCF"(peepTime)
      return if "PaO2/fiO2" is not null then
               "PaO2/fiO2"
             else
               (1) __
                 let paO2:     "PaO2 LOCF"(peepTime),
                     paO2Time: (convert paO2 to DateTime),
                     // TODO(moringenj): is this correct for fiO2?
                     fiO2:     "FiO2 LOCF"(peepTime)
                   // If the paO2 measurement is within 6 hours of the
                   // PEEP measurement, use the paO2 and fiO2
                   // measurements.  Otherwise assume mild ARDS by
                   // returning 300 'mm[Hg]' which is classified as mild
                   // below.
                   return if (duration in hours between paO2Time and peepTime) < 6 then
                            paO2 / fiO2
                          else
                            300 'mm[Hg]'

define function "Is mild ARDS"("PaO2/FiO2" Quantity):
  "PaO2/FiO2" > 200 'mm[Hg]'

define function "Recommended PEEP for PaO2"(peepTime DateTime):
  (1) _
    let FiO2:        "FiO2 LOCF"(peepTime),
        "PaO2/FiO2": "Ensure PaO2/FiO2"(peepTime)
      return if "Is mild ARDS"("PaO2/FiO2") then
               "Low PEEP for FiO2"(FiO2)
             else
               "High PEEP for FiO2"(FiO2)

define function "Is Conforming Tidal Volume"(tidalVolume Measurement):
  (1) _
    let tidalVolumeQuantity:  convert tidalVolume to Quantity,
        // TODO(moringenj): use an error-checking conversion
        tidalVolumeValue:     (convert tidalVolumeQuantity to 'mL').value,
        tidalVolumeTime:      convert tidalVolume to DateTime,
        // The function returns the ideal body weight converted/scaled to kg/m
        // not just any mass/length dimensions so taking the value out of the
        // quantity is well-defined.
        idealBodyWeight:      elm."Ideal Body Weight Measured or Computed Before"(
                                tidalVolumeTime
                              ),
        idealBodyWeightValue: idealBodyWeight.value
      return tidalVolumeValue in Interval[
                                   4 * idealBodyWeightValue,
                                   8 * idealBodyWeightValue
                                 ]

define function "Effective Plateau Pressure"(peepTime DateTime):
  (1) _
    let ventilationMode:            "Ventilation Mode"(peepTime),
        plateauPressureMeasurement: "Plateau Pressure Measurement LOCF"(peepTime)
      return if     plateauPressureMeasurement is null
                and ventilationMode = 'Pressure Driven' then
               "Peak Inspiratory Pressure LOCF"(peepTime)
             else
               plateauPressureMeasurement

define function "Is Conforming PEEP"(peepMeasurement Measurement):
  (1) _
    let peepQuantity:       convert peepMeasurement to Quantity,
        peepTime:           convert peepMeasurement to DateTime,
        tidalVolume:        "Tidal Volume LOCF"(peepTime),
        plateauPressure:    "Effective Plateau Pressure"(peepTime),
        pressureDifference: plateauPressure - peepQuantity,
        recommendedPEEP:    "Recommended PEEP for PaO2"(peepTime)
      return     peepQuantity >= recommendedPEEP
             and if tidalVolume is not null then
                   "Is Conforming Tidal Volume"(tidalVolume)
                 else
                   false
             and plateauPressure <= 30 'cm[H2O]'
             and pressureDifference <= 14 'cm[H2O]'

define "Conforming PEEP Measurements":
  ("PEEP Measurements") p where "Is Conforming PEEP"(p) return all p

// Quality Indicator

// TODO(moringenj): We require that all conditions are fulfilled within a visit.
//                  Is that logic correct?
define function "Is in Initial Population"(visitInterval Interval<DateTime>):
      Exists("Ventilation Procedures" p
               where (convert p to Interval<DateTime>)
                     overlaps visitInterval)
  and Exists("Intubation Tube Exposures" d
               where (convert d to Interval<DateTime>)
                      overlaps visitInterval)
  and Exists("ARDS Conditions" c
               where (convert c to Interval<DateTime>)
                     overlaps visitInterval)
  and AgeInYearsAt(start of visitInterval) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let visitInterval:               visitWithPeriods.visit,
        inInitialPopulationForVisit: "Is in Initial Population"(visitInterval),
        measurementsInVisit:         ("PEEP Measurements") m
                                       where m in visitInterval
                                       return all m
      return all (visitWithPeriods.fullyContainedPeriods) period
                   let measurementsInPeriod: (measurementsInVisit) m
                                               where m in period
                                               return all m,
                       goodMeasurements:     (measurementsInPeriod) m
                                               where "Is Conforming PEEP"(m)
                                               return all m,
                       numerator:            Count(goodMeasurements),
                       denominator:          Count(measurementsInPeriod)
                     return all elm."Period Result"(period,
                                                    inInitialPopulationForVisit,
                                                    numerator,
                                                    denominator)

define Result: elm."Overall Result"(Patient, "Visit Results")
