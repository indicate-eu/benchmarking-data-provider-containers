library "Main" version '0.0.0'

using OMOP version 'v5.4.MIMIC'

include OMOPFunctions

include "IndicateQiElements" called "E"

include "IndicateQi01Ventilation"              called "Qi01"
include "IndicateQi02Weaning"                  called "Qi02"
include "IndicateQi03Feeding"                  called "Qi03"
include "IndicateQi04GlucoseControl"           called "Qi04"
include "IndicateQi05ThromboembolicPrevention" called "Qi05"
include "IndicateQi06InfectionRate"            called "Qi06"
include "IndicateQi07PainSedationDelir"        called "Qi07"
include "IndicateQi08AdvanceCarePlan"          called "Qi08"
include "IndicateQi09Mobilisation"             called "Qi09"

define NoMatchingConcept: OMOPFunctions.SC(0)

define function ToObservation(
    indicatorConceptId Integer,
    result             Tuple{
                         patient      OMOP.Person,
                         reviewPeriod Interval<DateTime>,
                         periods      List<Tuple{
                                        period      Interval<DateTime>,
                                        numerator   Integer,
                                        denominator Integer,
                                        qi          Decimal
                                      }>
                       }
  ):
  if Exists((result.periods) p where p.qi is not null) then
    (result.periods) p
      where p.qi is not null
      return all OMOP.Observation{
        observationConceptId:   indicatorConceptId,
        observationTypeConcept: NoMatchingConcept,
        observationDatetime:    start of p.period,
        observationDate:        date from start of p.period,
        person:                 null, // result.patient.personId,
        valueAsNumber:          p.qi
      }
  else
    {}

context Patient

define Results:
  Flatten({
    ToObservation(2000100101, "Qi01".Result),
    ToObservation(2000100102, "Qi02".Result),
    ToObservation(2000100103, "Qi03".Result),
    ToObservation(2000100104, "Qi04".Result),
    ToObservation(2000100105, "Qi05".Result),
    ToObservation(2000100106, "Qi06".Result),
    ToObservation(2000100107, "Qi07".Result),
    ToObservation(2000100108, "Qi08".Result),
    ToObservation(2000100109, "Qi09".Result)
  })
