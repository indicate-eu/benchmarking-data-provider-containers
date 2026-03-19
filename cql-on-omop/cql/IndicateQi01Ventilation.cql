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
//
// Numerator:
//
// Denominator:
//

library "IndicateQi01Ventilation" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include TimePeriods called T
include IndicateQiElements called elm

code "ARDS Condition": '4195694' from elm.OMOPSV // ICD10 based code: '45552897'

code "Intubated (Tube Present)": '4097216' from elm.OMOPSV

concept "Intubation Tube": {
  "Intubated (Tube Present)"
}

code "Invasive Ventilation Procedure": '37158404' from elm.OMOPSV

concept "Ventilation Procedure": {
  "Invasive Ventilation Procedure"
}

code "Ventilation Mode": '37042784' from elm.OMOPSV

code "PaO2/FiO2 Measurement": '3029943' from elm.OMOPSV

code "PaO2 Default Measurement":              '3027801' from elm.OMOPSV
code "PaO2 Temperature Adjusted Measurement": '3022803' from elm.OMOPSV

concept "PaO2 Measurement": {
  "PaO2 Default Measurement",
  "PaO2 Temperature Adjusted Measurement"
}

code "FiO2 Measurement": '4353936' from elm.OMOPSV

code "PEEP Total, Measured Measurement": '42527140' from elm.OMOPSV
code "PEEP Setting Measurement":         '4216746'  from elm.OMOPSV
code "PEEP General Measurement":         '4353713'  from elm.OMOPSV

concept "PEEP Measurement": {
  "PEEP Total, Measured Measurement",
  "PEEP Setting Measurement",
  "PEEP General Measurement"
}

code "Plateau Pressure Measurement": '44782825' from elm.OMOPSV

 // Unit cmH2O
code "Inspiratory Pressure Setting": '4215838' from elm.OMOPSV
 // Unit mmHg, CAVE different units, has to be converted to unit cmH2O
code "Peak Inspiratory Pressure Measurement": '4101694' from elm.OMOPSV

code "Tidal Volume Inspiratory Measurement":  '44782826' from elm.OMOPSV
code "Tidal Volume Spontaneuous Measurement": '4108448'  from elm.OMOPSV
code "Tidal Volume Setting Measurement":      '3012410'  from elm.OMOPSV
code "Tidal Volume General Measurement":      '4029625'  from elm.OMOPSV

concept "Tidal Volume Measurement": {
  "Tidal Volume Inspiratory Measurement",
  "Tidal Volume Spontaneuous Measurement",
  "Tidal Volume Setting Measurement",
  "Tidal Volume General Measurement"
}

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

// Sorted in reverse chronological order for "Last Observation Carried Forward"
// logic below.
define "PaO2 Measurements":
  [Measurement: "PaO2 Measurement"] m
    return all m
    sort by measurementDatetime desc

define "FiO2 Measurements":
  [Measurement: "FiO2 Measurement"] m
    return all m
    sort by measurementDatetime desc

define "PaO2/FiO2 Measurements":
  [Measurement: "PaO2/FiO2 Measurement"] m
    return all m
    sort by measurementDatetime desc

define "PEEP Measurements":
  [Measurement: "PEEP Measurement"] m
    return all m
    sort by measurementDatetime

define "Ventilation Mode Obserations":
  [Observation: "Ventilation Mode"]

define "Plateau Pressure Measurements":
  [Measurement: "Plateau Pressure Measurement"] m
    return all m
    sort by measurementDatetime desc

define "Peak Inspiratory Pressure Measurements":
  (Flatten({
     ([Measurement: "Peak Inspiratory Pressure Measurement"] m
        return all {
          datetime: convert m to DateTime,
          quantity: convert (convert m to Quantity) to 'cm[H2O]'
        }
     ),
     ([Observation: "Inspiratory Pressure Setting"] o
        return all {
          datetime: convert o to DateTime,
          quantity: convert o to Quantity
        }
     )
   })) q
    return all q
    sort by datetime desc

define "Ventilation Procedures":
  [ProcedureOccurrence: "Ventilation Procedure"]

define "Intubation Tube Exposures":
  [DeviceExposure: "Intubation Tube"]

define "ARDS Conditions":
  [ConditionOccurrence: "ARDS Condition"]

// Last Observation Carried Forward
define function "PaO2 LOCF"(targetTime DateTime):
  First("PaO2 Measurements" m
          // TODO(moringenj): what is the correct logic and acceptable
          //                  precision for comparing times in this context?
          where (convert m to DateTime) same hour or before targetTime
          return all m)

define function "FiO2 LOCF"(targetTime DateTime):
  First("FiO2 Measurements" m
          where (convert m to DateTime) same hour or before targetTime
          return all m)

define function "PaO2/FiO2 LOCF"(targetTime DateTime):
  First("PaO2/FiO2 Measurements" m
          where (convert m to DateTime) same hour or before targetTime
          return all m)

define function "Plateau Pressure Measurement LOCF"(targetTime DateTime):
  First("Plateau Pressure Measurements" m
          where (convert m to DateTime) same hour or before targetTime
          return all m)

define function "Peak Inspiratory Pressure LOCF"(targetTime DateTime):
  First("Peak Inspiratory Pressure Measurements" m
          where m.datetime same hour or before targetTime
          return all m.quantity)

define "Usable Tidal Volume Measurements":
  [Measurement: "Tidal Volume Measurement"] m
    where     if m.unitConcept is null then
                // TODO(moringenj): include the measurement in the message once we have ToString for Measurement
                Message(false, true, '400', 'Warning', 'Tidal volume measurement does not have a unit')
              else
                true
          and if m.valueAsNumber is null then
                Message(false, true, '400', 'Warning', 'Tidal volume measurement does not have a numeric value')
              else
                true
          and if (convert (convert m to Quantity) to 'mL').value is null then
                Message(false, true, '400', 'Warning',
                        'Tidal volume measurement has unit "'
                        + (convert m to Quantity).unit
                        + '" but must convertible to "mL"')
              else
                true
    return all m
    sort by measurementDatetime desc

define function "Tidal Volume LOCF"(targetTime DateTime):
  First(("Usable Tidal Volume Measurements") m
          where m same hour or before targetTime
          return all m)

// PaO2 unit mm[Hg]
// FiO2 unit %
define function "Ensure PaO2/FiO2"(peepTime DateTime):
  (1) _
    let "PaO2/fiO2": "PaO2/FiO2 LOCF"(peepTime)
      return if "PaO2/fiO2" is not null then
               "PaO2/fiO2"
             else
               (1) __
                 let paO2: "PaO2 LOCF"(peepTime),
                     // TODO(moringenj): is this correct for fiO2?
                     fiO2: "FiO2 LOCF"(peepTime)
                   return if (duration in hours between
                              (convert paO2 to DateTime) and peepTime)
                             < 6 'h' then
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
    let tidalVolumeQuantity: convert tidalVolume to Quantity,
        tidalVolumeValue:    (convert tidalVolumeQuantity to 'mL').value,
        idwValue:            elm."Ideal Body Weight Measured or Computed".value
      return tidalVolumeValue in Interval[4 * idwValue, 8 * idwValue]

define function "Effective Plateau Pressure"(peepMeasurement Measurement):
  (1) _
    let peepMeasurementTime: convert peepMeasurement to DateTime
      // TODO(moringenj): Implement ventilation mode
      return if false then // "Ventilation Mode" ~ "Volume Driven Ventilation" then
               "Plateau Pressure Measurement LOCF"(peepMeasurementTime)
             else
               "Peak Inspiratory Pressure LOCF"(peepMeasurementTime)

define function "Is Conforming PEEP"(peepMeasurement Measurement):
  (1) _
    let peepQuantity:       convert peepMeasurement to Quantity,
        peepTime:           convert peepMeasurement to DateTime,
        tidalVolume:        "Tidal Volume LOCF"(peepTime),
        plateauPressure:    "Effective Plateau Pressure"(peepMeasurement),
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
define function "Is in Initial Population"(visit VisitOccurrence):
  (1) _
    let visitInterval: convert visit to Interval<DateTime>
      return     Exists("Ventilation Procedures" p
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
    let visitInterval:               convert (visitWithPeriods.visit as OMOP.VisitOccurrence) to Interval<DateTime>,
        inInitialPopulationForVisit: "Is in Initial Population"(visitWithPeriods.visit),
        measurementsInVisit:         ("PEEP Measurements") m
                                       where m in visitInterval
                                       return all m
      return all (visitWithPeriods.periods as List<Interval<DateTime>>) period
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
