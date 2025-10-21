SELECT fakultas, COUNT(*) AS jumlah_mahasiswa
FROM mahasiswa
GROUP BY fakultas;