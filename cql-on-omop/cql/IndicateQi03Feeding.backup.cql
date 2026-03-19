// Name     03 - Feeding
// Version  1.0
//
// Description:
//   Early enteral nutrition and calorie target met.
//
// Numerator:
//   For each 24 hour period starting at admission + 24 hours the calorie
//   intake has to be 10 % lower/higher than the individualised daily calorie
//   target.
//   First 24 hours and incomplete last 24 hour period are excluded.
//
// Denominator:
//   Number of 24 hour periods.
//   First 24 hours and incomplete last 24 hour period are excluded.

library "IndicateQi03Feeding" version '1.0.0'

using OMOP version 'v5.4.MIMIC'

include OMOPHelpers
include OMOPFunctions
include Drugs
include LocalTimeGermany called L
include TimePeriods called T
include IndicateQiElements called elm
include InsulinDrugs


// unit [cal]
code "Energy Requirement": '4022415' from elm.OMOPSV

/*Contraindication to enteral feeding:
- 4141768*/

// unit  [cal]
code "Calorie Intake Total 24 Hour": '3026267' from elm.OMOPSV

code "CO2 Production Rate": '21490580' from elm.OMOPSV

/*Calorie intake total:
- 3007882*/

code "Continuous Venovenous Hemofiltration":    '4051330' from elm.OMOPSV
code "Continuous Venovenous Hemodialysis":      '4051329' from elm.OMOPSV
code "Continuous Venovenous Hemodiafiltration": '4049846' from elm.OMOPSV
code "Intermittent Hemodialysis":               '4051326' from elm.OMOPSV

concept "Renal Replacement Therapy": {
  "Continuous Venovenous Hemofiltration",
  "Continuous Venovenous Hemodialysis",
  "Continuous Venovenous Hemodiafiltration",
  "Intermittent Hemodialysis"
}

code "Phosphate Serum": '3003458' from elm.OMOPSV
code "Phosphate Blood": '3018913' from elm.OMOPSV

concept "Phosphate Measurement": {
  "Phosphate Serum",
  "Phosphate Blood"
}

define "Insulin Drugs": InsulinDrugs."Insulin Drugs"

context Patient

define "Body Mass Index":
  elm."Most Recent Body Weight Measurement"
  / elm."Most Recent Body Height Measurement"

// Measurements and Procedures

define "Phosphate Measurements":
  [Measurement: "Phosphate Measurement"] m
    return all m
    sort by measurementDatetime desc

define "Insulin Exposures":
  [DrugExposure: "Insulin Drugs"]

define "Energy Requirement Measurements":
  [Measurement: "Energy Requirement"] m
    return all m
    sort by measurementDatetime desc

define "CO2 Production Rate Measurements":
  [Measurement: "CO2 Production Rate"]

define "Calorie Intake Measurements":
  [Measurement: "Calorie Intake Total 24 Hour"]

define "Renal Replacement Therapy Procedures":
  [ProcedureOccurrence: "Renal Replacement Therapy"]

define function "Last Phosphate Measurement in Period"(period Interval<DateTime>):
  (1) _
    let lastMeasurement: Last("Phosphate Measurements" m
                                where m.measurementDatetime in period
                                return all m)

      // the specification states that if there is not phosphate
      // measurement in the period, assume it was normal, that is
      // greater than 0.65 mmol/l.
      return if lastMeasurement is null then
               1 'mmol/L'
             else
               convert lastMeasurement to Quantity

define function "Max Insulin Measurement in Period"(period Interval<DateTime>):
  Max("Insulin Exposures" m
        where (convert m to Interval<DateTime>) overlaps period
        // No registered conversion at the moment
        return all OMOPFunctions.ToQuantity(m))

define function "Last Energy Requirement Measurement in Period"(period Interval<DateTime>):
  Last("Energy Requirement Measurements" m
         where m.measurementDatetime in period
         return all m)

define function "Median CO2 Production Rate in Period"(period Interval<DateTime>):
  Median("CO2 Production Rate Measurements" m
           where (convert m to DateTime) in period
           return all convert m to Quantity)

define function "Calorie Intake in Period"(period Interval<DateTime>):
  // There should be exactly one such measurement in each 24-hour period.
  (1) _
    let measurement: First("Calorie Intake Measurements" m
                             where m in period
                             return all m)
      return convert measurement to Quantity

define function "Renal Replacement Therapy Procedure in Period"(period Interval<DateTime>):
  Exists("Renal Replacement Therapy Procedures" p
           where (convert p to Interval<DateTime>) during period
           return all p)

//

define function "Initial Calorie Target via CO2 Production Rate"(previousPeriod Interval<DateTime>):
  Quantity{
    value: "Median CO2 Production Rate in Period"(previousPeriod).value
           * 8.19
           * if "Body Mass Index" < 30 then
              1
             else
              0.6,
    unit: 'kcal'
  }

define "Initial Calorie Target via BMI":
  case
    when "Body Mass Index" < 30 then
      24 'kcal/d/kg' * (convert elm."Most Recent Body Weight Measurement" to Quantity) // TODO(moringenj): use time-dependent body weight
    when "Body Mass Index" <= 50 then
      14 'kcal/d/kg' * (convert elm."Most Recent Body Weight Measurement" to Quantity)
    else
      24 'kcal/d/kg'
      * Quantity{
          value: (48.4 + 77 * ((convert elm."Most Recent Body Height Measurement" to Quantity) - 1.5 'm').value), // TODO(moringenj): use existing "Ideal Body Weight"
          unit:  'kg'
        }
  end

define function "Initial Calorie Target"(previousDay Interval<DateTime>):
  (1) _
    // TODO(moringenj): what temporal interval should we consider for the energy requirement
    let energyRequirement: "Last Energy Requirement Measurement in Period"(previousDay)
      return if energyRequirement is not null then
               energyRequirement
             else if "Median CO2 Production Rate in Period"(previousDay) is not null then
               "Initial Calorie Target via CO2 Production Rate"(previousDay)
             else
               "Initial Calorie Target via BMI"

define function "Calorie Target for 24-hour Period"(previousTarget Quantity,
                                                    previousPeriod Interval<DateTime>,
                                                    period         Interval<DateTime>,
                                                    dayOfVisit     Integer):
  (1) _
    let initialCalorieTarget: "Initial Calorie Target"(previousPeriod)
      return case
               when dayOfVisit = 0 then
                 null // No target for first 24-hour period

               when dayOfVisit = 1 then
                 0.75 * initialCalorieTarget

               when     not "Renal Replacement Therapy Procedure in Period"(previousPeriod)
                    and "Last Phosphate Measurement in Period"(period) < 0.65 'mmol/l'
                    and "Max Insulin Measurement in Period"(previousPeriod) <= 4 '[IU]/h'
                    and previousTarget >= 0.5 * initialCalorieTarget then
                 0.25 * initialCalorieTarget

               when     "Max Insulin Measurement in Period"(previousPeriod) < 2 '[IU]/h'
                    and previousTarget < initialCalorieTarget then
                 previousTarget + 0.25 * initialCalorieTarget

               when     "Max Insulin Measurement in Period"(previousPeriod)
                        in Interval[2 '[IU]/h', 4 '[IU]/h']
                    and previousTarget > 0 then
                 previousTarget - 0.25 * initialCalorieTarget

               when     "Max Insulin Measurement in Period"(previousPeriod) > 4 '[IU]/h'
                    and previousTarget > 0 then
                 previousTarget - 0.5 * initialCalorieTarget

               else // TODO(moringenj):
                 null

             end

define function "24-hour Periods with Results"(periods List<Interval<DateTime>>):
  (periods) p aggregate r starting  ({
                                       previousPeriod: null,
                                       previousTarget: null,
                                       dayOfVisit:     0,
                                       results:        {},
                                       debug: {}
                                     }):
    (1) _
      let target: "Calorie Target for 24-hour Period"(
                    r.previousPeriod,
                    r.previousTarget,
                    p,
                    r.dayOfVisit
                  ),
          actual: "Calorie Intake in Period"(p),
          result: 0.9 * target <= actual and actual <= 1.1 * target
        return {
                 previousPeriod: p,
                 previousTarget: target,
                 dayOfVisit:     r.dayOfVisit + 1,
                 results:        Flatten({r.results, {{period: p, result: result}}}),
                 debug:          Flatten({r.debug,   {{
                                                        previousPeriod: r.previousPeriod,
                                                        previousTarget: r.previousTarget,
                                                        period:         p,
                                                        dayOfVisit:     r.dayOfVisit,
                                                        phosphate:      "Last Phosphate Measurement in Period"(p),
                                                        insulin:        "Max Insulin Measurement in Period"(r.previousPeriod),
                                                        result:         result
                                                      }}})
               }

/*define function "24-hour Periods with appropriate Calorie Intake"(periods List<Interval<DateTime>>):
  (periods) p
    let actual: "Calorie Intake in 24-hour period"(p)
        target: "Calorie Target for 24-hour period"(p, TODO)
      where 0.9 * target <= actual and actual <= 1.1 target*/

// 24 h Periods

// In this variant, the first period for each visit starts at the
// start datetime of the visit and the other follow from that.
/*define function "24-hour Periods during Visit"(visit VisitOccurrence):
  (1) _
    let periodInterval: convert visit to Interval<DateTime>,
        dayDuration:    Quantity{value: (convert 1 'd' to 's').value, unit: 'seconds'}
      return (Expand(periodInterval, dayDuration)) s
               let shift: Interval[s, s + dayDuration)
                 where shift included in periodInterval // TODO(moringenj): always true?
                 return all shift*/

// In this variant, each period start at 6:00 and ends 24 h later at
// 5:59. All periods of this kind that fall within the visits are
// initially generated even though some of those at the beginning and at
// the end of the visit may not be used due to exclusion rules.
define function "24-hour Periods during Visit"(visit VisitOccurrence):
  (1) _
    let periodInterval:   convert visit to Interval<DateTime>,
        periodStartDay:   date from start of periodInterval,
        periodEnd:        end of periodInterval,
        firstPeriodStart: L.ExpandDateToDateTime(periodStartDay) + 6 hours,
        dayDuration:      Quantity{value: (convert 1 'd' to 's').value, unit: 'seconds'}
      return if firstPeriodStart before periodEnd then
               (Expand(Interval[firstPeriodStart, periodEnd], dayDuration)) s
                 let period: Interval[s, s + dayDuration)
                   where period included in periodInterval
                   return all period
             else
               {}

define "24-hour Periods during Visits":
  (elm."Intensive Care Visits in Review Period") v
    let periods: "24-hour Periods during Visit"(v)
      where Exists(periods)
      return all periods

define "24-hour Periods with appropriate Calorie Intake during Visits":
  "24-hour Periods during Visits" periods
    return all ("24-hour Periods with Results"(periods).results) r
                 where (r as Tuple{result Boolean, period Interval<DateTime>}).result
                 return all (r as Tuple{result Boolean, period Interval<DateTime>}).period

define "24-hour Periods":
  Flatten("24-hour Periods during Visits")

define "24-hour Periods with appropriate Calorie Intake":
  Flatten("24-hour Periods with appropriate Calorie Intake during Visits")

/*define debug:
  ("24-hour Periods during Visits") periods
    return all "24-hour Periods with appropriate Calorie Intake"(periods)*/

// Quality Indicator

define "Is in Initial Population":
      Exists(elm."Intensive Care Visits in Review Period")
  //and (elm."Age at Start of Review Period" >= 18)

define "24-hour Periods Results":
  (T."24-hour Periods in Visits") periods
    return all (periods) p
                 let numerator:   Count(("24-hour Periods with appropriate Calorie Intake") s
                                          where (p as Interval<DateTime>) includes (s as Interval<DateTime>) return all s),
                     denominator: Count(("24-hour Periods") s
                                          where (p as Interval<DateTime>) includes (s as Interval<DateTime>) return all s)
                   return all {
                     period:      p as Interval<DateTime>,
                     numerator:   numerator,
                     denominator: denominator,
                     qi:          if "Is in Initial Population" then
                                    numerator / denominator
                                  else
                                    null
                   }

/*define Denominator:
  Count("24-hour Periods with appropriate Calorie Intake")

define Numerator:
  Count("24-hour Periods")

define QI:
  if "Is in Initial Population" then
    Numerator / Denominator
  else
    null*/

define Result:
  {
    patient:      Patient,
    reviewPeriod: elm."Review Period",
    periods:      Flatten("24-hour Periods Results")
  }

define debugResult:
  {
  /*insulin: "Insulin Exposures" e return all e, //OMOPFunctions.ToQuantity(e)
    co2: "CO2 Production Rate Measurements" m return all {t: m.measurementDatetime, v: convert m to Quantity} sort by t,
    mco2: Median("CO2 Production Rate Measurements" m return convert m to Quantity),
  w: elm."Most Recent Body Weight Measurement",
  h: elm."Most Recent Body Height Measurement"*/
  r: "Renal Replacement Therapy Procedures" m return all m
  }
