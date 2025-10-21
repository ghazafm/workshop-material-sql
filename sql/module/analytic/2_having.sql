SELECT fakultas, AVG(ujian) AS rata_ujian
FROM mahasiswa
GROUP BY fakultas
HAVING AVG(ujian) > 75;
