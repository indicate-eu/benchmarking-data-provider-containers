// Name     04 - Glucose Control
// Version  1.0
//
// Description:
//   The blood glucose levels of critically ill patients should be kept
//   within an acceptable range.  Regular measurements, at least once
//   per shift and possibly corrective treatments are required.  The type
//   of treatment differs depending on the type of derangement of blood
//   glucose disorder, and is not included in this quality indicator.

library "IndicateQi04GlucoseControl" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include IndicateQiElements called elm
include IndicateQiUtilities called U
include TimePeriods called T

parameter "Acceptable Glucose Levels"
  default Interval[3.3 'mmol/L', 10.0 'mmol/L']

parameter "Maximum Time between consecutive Non-acceptable Glucose Levels"
  default 2 'h'

parameter "Maximum Time between consecutive Glucose Levels"
  default 10 'h'

code "Glucose in Arterial Blood (Mass/volume)":                 '3031266' from elm.OMOPSV
code "Glucose in Arterial Blood (Moles/volume)":                '3044242' from elm.OMOPSV
code "Glucose in Blood (Mass/volume)":                          '3000483' from elm.OMOPSV
code "Glucose in Blood (Moles/volume)":                         '3020491' from elm.OMOPSV
code "Glucose in Capillary Blood (Mass/volume)":                '3004077' from elm.OMOPSV
code "Glucose in Capillary Blood by Glucometer (Mass/volume)":  '3034962' from elm.OMOPSV
code "Glucose in Capillary Blood by Glucometer (Moles/volume)": '3001501' from elm.OMOPSV
code "Glucose in Mixed Venous Blood (Mass/volume)":             '1092148' from elm.OMOPSV
code "Glucose in Mixed Venous Blood (Moles/volume)":            '1761753' from elm.OMOPSV
code "Glucose in Serum or Plasma (Mass/volume)":                '3004501' from elm.OMOPSV
code "Glucose in Serum or Plasma (Moles/volume)":               '3013826' from elm.OMOPSV
code "Glucose in Venous Blood (Mass/volume)":                   '3033408' from elm.OMOPSV
code "Glucose in Venous Blood (Moles/volume)":                  '3038515' from elm.OMOPSV

concept "Glucose Level": {
  "Glucose in Arterial Blood (Mass/volume)",
  "Glucose in Arterial Blood (Moles/volume)",
  "Glucose in Blood (Mass/volume)",
  "Glucose in Blood (Moles/volume)",
  "Glucose in Capillary Blood (Mass/volume)",
  "Glucose in Capillary Blood by Glucometer (Mass/volume)",
  "Glucose in Capillary Blood by Glucometer (Moles/volume)",
  "Glucose in Mixed Venous Blood (Mass/volume)",
  "Glucose in Mixed Venous Blood (Moles/volume)",
  "Glucose in Serum or Plasma (Mass/volume)",
  "Glucose in Serum or Plasma (Moles/volume)",
  "Glucose in Venous Blood (Mass/volume)",
  "Glucose in Venous Blood (Moles/volume)"
}

define "Verified Maximum Time between consecutive Non-acceptable Glucose Levels":
  (1) _
    let converted: convert "Maximum Time between consecutive Non-acceptable Glucose Levels" to 'h'
      return if converted is null then
               Message(null, true, '400', 'Error',
                       '"Maximum Time between consecutive Non-acceptable Glucose Levels"'
                       + 'must be convertible to hours')
             else
               converted

define "Verified Maximum Time between consecutive Glucose Levels":
  (1) _
    let converted: convert "Maximum Time between consecutive Glucose Levels" to 'h'
      return if converted is null then
               Message(null, true, '400', 'Error',
                       '"Maximum Time between consecutive Glucose Levels"'
                       + 'must be convertible to hours')
             else
               converted

context Patient

// Glucose Measurements

define "Glucose Measurements":
  [Measurement: "Glucose Level"] m // TODO(moringenj): restrict to review period?
    return all m
    sort by measurementDatetime

define "Glucose Measurements With Neighbors":
  elm."Measurements with Neighbors"("Glucose Measurements")

// Glucose levels

define function "Ensure Glucose Level in mol/L"(measurement Measurement):
  U."EnsureQuantityIn mol/L"(
    'Blood Glucose Level', measurement, 'mg/dL', 'mmol/L', 1/18
  )

define function "Is High Glucose Level"(glucoseLevel Quantity):
  glucoseLevel > end of "Acceptable Glucose Levels"

define function "Is Low Glucose Level"(glucoseLevel Quantity):
  glucoseLevel < start of "Acceptable Glucose Levels"

define function "Is Acceptable Glucose Level"(glucoseLevel Quantity):
      (not "Is High Glucose Level"(glucoseLevel))
  and (not "Is Low Glucose Level"(glucoseLevel))

define function "Acceptable Follow-up Glucose Level"(firstValue  Quantity,
                                                     secondValue Quantity):
     "Is Acceptable Glucose Level"(secondValue)
  /* Below acceptable range but increased by at least 20 % */
  or (    "Is Low Glucose Level"(firstValue)
      and "Is Low Glucose Level"(secondValue)
      and secondValue > firstValue * 1.2)
  /* Above acceptable range but decreased by at least 20 % */
  or (    "Is High Glucose Level"(firstValue)
      and "Is High Glucose Level"(secondValue)
      and secondValue < firstValue * 0.8)

define function "Time between Measurements At Most"(earlierMeasurement Measurement,
                                                    laterMeasurement   Measurement,
                                                    maximumTime        Quantity):
  (1) _
    let maximumTimeInHours: (convert maximumTime to 'h').value
      return (difference in hours between (convert earlierMeasurement to DateTime)
                                  and     (convert laterMeasurement   to DateTime))
             <= maximumTimeInHours

define function "Successful Glucose Control"(previousMeasurement Measurement,
                                             measurement         Measurement,
                                             nextMeasurement     Measurement):
      (   (previousMeasurement is null)
       or "Time between Measurements At Most"(
            previousMeasurement,
            measurement,
            "Verified Maximum Time between consecutive Glucose Levels"
          ))
  and (1) _
        let measurementInMolL:     "Ensure Glucose Level in mol/L"(measurement),
            nextMeasurementInMolL: if nextMeasurement is not null then
                                     "Ensure Glucose Level in mol/L"(nextMeasurement)
                                   else
                                     null
          return
                    "Is Acceptable Glucose Level"(measurementInMolL)
                 or (if nextMeasurement is null then
                       false
                     else
                           "Time between Measurements At Most"(
                             measurement,
                             nextMeasurement,
                             "Verified Maximum Time between consecutive Non-acceptable Glucose Levels"
                           )
                       and "Acceptable Follow-up Glucose Level"(
                             measurementInMolL, nextMeasurementInMolL
                           ))

define function "Acceptable Glucose Measurements"(
    measurements List<Tuple{previous Measurement, current Measurement, next Measurement}>,
    isFirstShift Boolean
  ):
  // Do the first triple separately so that we can indicate that the
  // predecessor of the first measurement does not matter if the context is the
  // first shift of an ICU visit.
  Flatten({
    (1) _
      let first: First(measurements)
        return {
          "Successful Glucose Control"(
            if isFirstShift then null else first.previous,
            first.current,
            first.next
          )
        },
    (Tail(measurements)) m
      return all "Successful Glucose Control"(m.previous, m.current, m.next)
  })

define function "Conforming Glucose Measurements"(
    measurements List<Tuple{previous Measurement, current Measurement, next Measurement}>,
    isFirstShift Boolean
  ):
  if Exists(measurements) then
    AllTrue("Acceptable Glucose Measurements"(measurements, isFirstShift))
  else
    false

// Shifts

define function "Measurements during Shift Plus Neighbors"(shift Interval<DateTime>):
  "Glucose Measurements With Neighbors" m
    where (convert m.current to DateTime) during shift
    return all m

define function "Is Conforming Shift"(shift        Interval<DateTime>,
                                      isFirstShift Boolean):
  (1) _
    let shiftMeasurements: "Measurements during Shift Plus Neighbors"(shift)
      return "Conforming Glucose Measurements"(shiftMeasurements, isFirstShift)

define function "Conforming Shifts in Visit"(shifts List<Interval<DateTime>>):
  // Handle the first shift of each ICU visit specially since the
  // first measurement of that first shift does not have a preceding
  // measurement.
  Flatten({({ First(shifts) }) s
              where "Is Conforming Shift"(s, true)
              return all s,
           (Tail(shifts)) s
             where "Is Conforming Shift"(s, false)
             return all s})

// Quality Indicator

define function "Is in Initial Population"(visitInterval Interval<DateTime>):
  AgeInYearsAt(start of visitInterval) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let visitInterval:               visitWithPeriods.visit,
        inInitialPopulationForVisit: "Is in Initial Population"(visitInterval),
        // This returns only shifts that are fully contained in the
        // visit interval.  This behavior matches the requirement that
        // incomplete shifts which merely overlap the visit interval
        // should be ignored
        shifts:                      T."Shifts during Period"(visitInterval),
        goodShifts:                  "Conforming Shifts in Visit"(shifts)
      return all (visitWithPeriods.overlappingPeriods) period
                   // If the number of shifts during period is 0, the
                   // quotient will be 0/0 which evaluates to null so
                   // that the period result is recognized as
                   // denominator exclusion.
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     Count((goodShifts) s where s during period),
                     Count((shifts)     s where s during period)
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
