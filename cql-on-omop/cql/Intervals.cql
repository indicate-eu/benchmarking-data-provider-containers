library "Intervals" version '1.0.0'

/// Set operations for lists of intervals

define function UnionIntervals(Left List<Interval<DateTime>>,
                               Right List<Interval<DateTime>>):
  collapse(flatten({Left, Right}))

define function IntersectIntervals(Left List<Interval<DateTime>>,
                                   Right List<Interval<DateTime>>):
  from (Left) l, (Right) r where l overlaps r return all l intersect r

/*
 * Subtract a set of intervals from a given interval and return the
 * remaining (possibly empty) set of intervals.
 */
define function SubtractFromInterval(Base Interval<DateTime>,
                                     Except List<Interval<DateTime>>):
  ((flatten({Except,{null}})) i aggregate r starting ({intervals:{}, rest:Base}):
     case
       // Stop when there is no rest or no next interval.
       when r.rest is null then
         r
       when i is null then
         {intervals:flatten({r.intervals,{r.rest}}),rest:null}

       // |  i  |  |rest|  or  |rest|  |  i  |
       when end of i < start of r.rest or start of i > end of r.rest  then
         r

       //    |rest|
       // |     i    |
       when start of i <= start of r.rest and end of i >= end of r.rest then
         {intervals:r.intervals, rest:null}

       //     |rest|
       // |  i  |
       when start of i <= start of r.rest then
         (1) _
           let Rest: Interval[end of i, end of r.rest]
             return {intervals:r.intervals, rest:Rest}

       // |rest|
       //    |  i  |
       when end of i >= end of r.rest then
         (1) _
           let Segment: Interval[start of r.rest, start of i]
             return {intervals:flatten({r.intervals,{Segment}}), rest:null}

       // |   rest   |
       //   |  i  |
       else
         (1) _
           let Segment: Interval[start of r.rest, start of i],
               Rest: Interval(end of i, end of r.rest]
             return {intervals:flatten({r.intervals,{Segment}}), rest:Rest}
     end).intervals

/*
 * Subtract a set of intervals from a base set of intervals and return
 * the remaining (possibly empty) set of intervals.
 */
define function DifferenceIntervals(Left List<Interval<DateTime>>, Right List<Interval<DateTime>>):
  (1) _
    let Sorted:   (Right) r sort by low,
        Segments: (Left) l return all SubtractFromInterval(l, Sorted)
      return collapse(flatten(Segments))

/// "Careful" interval operations, that is preserving boundary properties

/**
 * Constructs a new Interval instance but unlike the standard
 * Interval[...] syntax, accepts two additional parameters that
 * control the openness of the boundaries.
 *
 * This function is useful when the openness of the interval
 * boundaries is not statically known but computed at runtime by a
 * Boolean expression.
 */
define function CarefulInterval(Low DateTime, LowClosed Boolean,
                                High DateTime, HighClosed Boolean):
  if LowClosed then
    if HighClosed then Interval[Low, High] else Interval[Low, High)
  else
    if HighClosed then Interval(Low, High] else Interval(Low, High)

/*
 * Like the standard function collapse but this function preserves the
 * exact boundary points and openness of the input intervals in the
 * result intervals.
 *
 * Example:
 *
 *   collapse({Interval[@2000-01-01T04:00:00, @2000-01-01T08:00:00),
 *             Interval[@2000-01-01T03:00:00, @2000-01-01T05:00:00]})
 *   => Interval<System.DateTime> [2000-01-01T03:00:00, 2000-01-01T07:59:59]
 *
 *   CarefulCollapse({Interval[@2000-01-01T04:00:00, @2000-01-01T08:00:00),
 *                    Interval[@2000-01-01T03:00:00, @2000-01-01T05:00:00]})
 *   => Interval<System.DateTime> [2000-01-01T03:00:00, 2000-01-01T08:00:00)
 *
 * Note the changed end point when using the standard collapse function.
 */
define function CarefulCollapse(Intervals List<Interval<DateTime>>):
  (collapse(Intervals)) i
    return all
      (1) _
        // For Low and High, we collect intervals that touch the
        // respective boundary and "prioritize" such that intervals which
        // are closed on that side are preferred since they correspond to
        // a larger set and the collapsed representation has to include
        // the boundary points.
        let Low:  First((Intervals) j
                          where start of i = start of j
                          return {i: j, closed: if j.lowClosed then 1 else 0}
                          sort by closed desc).i,
            High: First((Intervals) j
                          where end of i = end of j
                          return {i: j, closed: if j.highClosed then 1 else 0}
                          sort by closed desc).i
        return CarefulInterval(Low.low,   Low.lowClosed,
                               High.high, High.highClosed)

define function CarefulUnionIntervals(Left List<Interval<DateTime>>,
                                      Right List<Interval<DateTime>>):
  CarefulCollapse(flatten({Left, Right}))

define function CarefulIntersectIntervals(Left List<Interval<DateTime>>,
                                          Right List<Interval<DateTime>>):
  from (Left) l, (Right) r
    where l overlaps r
    // We need this case analysis because intersect changes the
    // interval boundaries, even in case one interval completely contains
    // the other. Example:
    //
    //   Interval[1,5) intersect Interval[0,10] => Interval<Integer> [1, 4]
    //
    // Note how the end point of the result is shifted and the result
    // inteval is no longer holf open.
    return all case
                 when l included in r then l
                 when l includes r then r
                 else
                   (1) _
                     let Intersection: l intersect r,
                         Low: if start of Intersection = start of l then
                                {endPoint: l.low, closed: l.lowClosed}
                              else
                                {endPoint: r.low, closed: r.lowClosed},
                         High: if end of Intersection = end of l then
                                 {endPoint: l.high, closed: l.highClosed}
                               else
                                 {endPoint: r.high, closed: r.highClosed}
                       return CarefulInterval(Low.endPoint,  Low.closed,
                                              High.endPoint, High.closed)
               end

/*
 * Like SubtractFromInterval, subtract a set of intervals from a given
 * interval and return the remaining (possibly empty) set of intervals
 * but unlike SubtractFromInterval, compute the exact boundary points
 * and openness for the result intervals.
 *
 * For example consider [1, 5] - [3, 4] and [1, 5] - (3, 4]. In the
 * first case, the end point 3 is subtracted and thus excluded from
 * the result. The second example behaves in the opposite way:
 *
 *   [1, 5] - [3, 4] => [1, 3)
 *   [1, 5] - (3, 4] => [1, 3]
 *
 * The example uses Interval<Integer> for simplicity but the same
 * logic applies for Interval<DateTime>.
 */
define function CarefulSubtractFromInterval(Base Interval<DateTime>,
                                            Except List<Interval<DateTime>>):
  ((flatten({Except,{null}})) i aggregate r starting ({intervals:{}, rest:Base}):
     case
       // Stop when there is no rest or no next interval.
       when r.rest is null then
         r
       when i is null then
         {intervals:flatten({r.intervals,{r.rest}}),rest:null}

       // |  i  |  |rest|  or  |rest|  |  i  |
       when end of i < start of r.rest or start of i > end of r.rest  then
         r

       //    |rest|
       // |     i    |
       when start of i <= start of r.rest and end of i >= end of r.rest then
         {intervals:r.intervals, rest:null}

       //     |rest|
       // |  i  |
       when start of i <= start of r.rest then
         (1) _
           let iTyped: i as Interval<DateTime>,
               Rest:   CarefulInterval(iTyped.high, not iTyped.highClosed,
                                       r.rest.high, r.rest.highClosed)
             return {intervals:r.intervals, rest:Rest}

       // |rest|
       //    |  i  |
       when end of i >= end of r.rest then
         (1) _
           let iTyped:  i as Interval<DateTime>,
               Segment: CarefulInterval(r.rest.low, r.rest.lowClosed,
                                        iTyped.low, not iTyped.lowClosed)
             return {intervals:flatten({r.intervals,{Segment}}), rest:null}

       // |   rest   |
       //   |  i  |
       else
         (1) _
           let iTyped:  i as Interval<DateTime>,
               Segment: CarefulInterval(r.rest.low, r.rest.lowClosed,
                                        iTyped.low, not iTyped.lowClosed),
               Rest:    CarefulInterval(iTyped.high, not iTyped.highClosed,
                                        r.rest.high, r.rest.highClosed)
             return {intervals:flatten({r.intervals,{Segment}}), rest:Rest}
     end).intervals

define function CarefulDifferenceIntervals(Left List<Interval<DateTime>>,
                                           Right List<Interval<DateTime>>):
  (1) _
    let Sorted:   (Right) r sort by low,
        Segments: (Left) l return all CarefulSubtractFromInterval(l, Sorted)
      return CarefulCollapse(flatten(Segments))

/// Other interval utilities

define function CleanIntervals(Intervals List<Interval<DateTime>>):
  CarefulCollapse((Intervals) i where not (i.low = i.high) return all i)

define function SameValue(left Any, right Any):
  case
    when left is Boolean and right is Boolean then
      (left as Boolean) = (right as Boolean)
    when left is Integer and right is Integer then
      (left as Integer) = (right as Integer)
    when left is Decimal and right is Decimal then
      (left as Decimal) = (right as Decimal)
    when left is Quantity and right is Quantity then
      (left as Quantity) = (right as Quantity)
    else
      false
  end

// Example:
// PointsToIntervals({{time: Now(),            value: 1},
//                    {time: Now() + 1 'hour', value: 2},
//                    {time: Now() + 2 'hour', value: 1}},
//                   Now() + 5 'hour')
// => { {time: Interval[@2025-04-15T14:07:50.788+02:00,
//                      @2025-04-15T15:07:50.788+02:00]
//       value: 1},
//      {time: Interval[@2025-04-15T15:07:50.788+02:00,
//                      @2025-04-15T16:07:50.788+02:00]
//       value: 2},
//      {time: Interval[@2025-04-15T16:07:50.788+02:00,
//                      @2025-04-15T19:07:50.788+02:00]
//       value: 1} }
define function PointsToIntervals(Points  List<Tuple{time DateTime, value Any}>,
                                  EndTime DateTime):
  if Exists(Points) then
    PointsToIntervalsInterval(
      // Add sentinal after last proper element
      flatten({(Points) p where p.time < EndTime return all p, {null}}
              as List<List<Tuple{time DateTime, value Any}>>),
      EndTime
    )
  else
    {}

// This function is called by PointsToIntervals2 with the following
// pre-conditions:
// 1. This function is not called when Intervals is the empty list
// 2. PointsToIntervals2 adds a final "sentinel" element to Intervals
//    before calling this function
define function PointsToIntervalsInterval(Intervals List<Tuple{time DateTime, value Any}>,
                                          EndTime   DateTime):
  ((Intervals) e aggregate r starting ({previous: null , intervals: {}}):
    if e is null then // sentinel
      {
        previous:  r.previous, // unused since we are done
        intervals: flatten({
                     r.intervals,
                     { {
                       time:  Interval[
                                start of (r.previous as Tuple{time Interval<DateTime>, value Any}).time,
                                EndTime
                              ],
                       value: (r.previous as Tuple{time Interval<DateTime>, value Any}).value
                     } }
                   })
      }
    else if r.previous is null then
      { previous: {time: Interval[e.time, e.time], value: e.value}, intervals: r.intervals }
    else if SameValue((r.previous as Tuple{time Interval<DateTime>, value Any}).value, e.value) then
      {
        previous: {
          time:  Interval[start of (r.previous as Tuple{time Interval<DateTime>, value Any}).time, e.time],
          value: e.value
        },
        intervals: r.intervals
      }
    else
      {
        previous:  {time: Interval[e.time, e.time], value: e.value},
        intervals: if start of (r.previous as Tuple{time Interval<DateTime>, value Any}).time < e.time then
                     flatten({
                       r.intervals,
                       { {
                         time:  Interval[start of (r.previous as Tuple{time Interval<DateTime>, value Any}).time, e.time],
                         value: (r.previous as Tuple{time Interval<DateTime>, value Any}).value
                       } }
                     })
                   else
                     r.intervals
      }
  ).intervals
