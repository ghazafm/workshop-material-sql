CREATE TABLE fakultas (
    kode VARCHAR(5) PRIMARY KEY,
    nama_fakultas VARCHAR(100) NOT NULL
);

ALTER TABLE mahasiswa
ADD CONSTRAINT fk_fakultas
FOREIGN KEY (fakultas) REFERENCES fakultas(kode);

INSERT INTO fakultas (kode, nama_fakultas) VALUES
  ('FILK', 'Fakultas Ilmu Komputer'),
  ('FEB',  'Fakultas Ekonomi dan Bisnis'),
  ('FT',   'Fakultas Teknik'),
  ('FISIP','Fakultas Ilmu Sosial dan Ilmu Politik'),
  ('FIB',  'Fakultas Ilmu Budaya');

SELECT m.nama, m.fakultas, f.nama_fakultas
FROM mahasiswa m
JOIN fakultas f
ON m.fakultas = f.kode;

SELECT * FROM fakultas;