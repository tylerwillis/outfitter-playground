/**
 * Split an amount of money evenly among a number of people.
 *
 * @param {number} amount - total to split, in dollars (e.g. 100 or 89.97)
 * @param {number} people - how many people share the bill
 * @returns {number[]} one share per person, in dollars
 */
export function split(amount, people) {
  if (!Number.isFinite(amount) || amount < 0) {
    throw new RangeError(`amount must be a non-negative number, got ${amount}`);
  }
  if (!Number.isInteger(people) || people < 1) {
    throw new RangeError(`people must be a positive integer, got ${people}`);
  }
  const cents = Math.round(amount * 100);
  const baseShare = Math.floor(cents / people);
  const remainder = cents % people;
  return Array.from(
    { length: people },
    (_, index) => (baseShare + (index < remainder ? 1 : 0)) / 100,
  );
}

/** Format a dollar value for display. */
export function formatDollars(value) {
  return `$${value.toFixed(2)}`;
}
