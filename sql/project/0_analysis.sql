SELECT * FROM ncr_ride_bookings;

SELECT "Booking Status" FROM ncr_ride_bookings
WHERE "Booking Status" IN ('Completed');

SELECT "Booking Status" FROM ncr_ride_bookings
WHERE "Booking Status" LIKE ('Completed');

SELECT "Booking Status" FROM ncr_ride_bookings
WHERE "Booking Status" IN ('%ted');

SELECT "Booking Status" FROM ncr_ride_bookings
WHERE "Booking Status" LIKE ('%ted');

SELECT "Booking Status" FROM ncr_ride_bookings
WHERE "Booking Status" NOT ILIKE ('completed');

SELECT "Booking Status" FROM ncr_ride_bookings
WHERE "Booking Status" LIKE 'in%'

SELECT "Booking Status" FROM ncr_ride_bookings
WHERE "Booking Status" ILIKE 'in%'

SELECT * FROM ncr_ride_bookings;

SELECT count(*) FROM ncr_ride_bookings
WHERE "Avg VTAT" = NULL;

SELECT count(*) FROM ncr_ride_bookings
WHERE "Avg VTAT" = 'null';