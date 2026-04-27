insert into public.local_welfare_region_queue
  (region, sub_region, area_detail, source_prefix, seed_urls, seed_titles, status, priority)
values
  ('서울', '종로구', '', '종로구', '["https://www.jongno.go.kr"]'::jsonb, '{"https://www.jongno.go.kr":"종로구청"}'::jsonb, 'pending', 100),
  ('서울', '중구', '', '중구', '["https://www.junggu.seoul.kr"]'::jsonb, '{"https://www.junggu.seoul.kr":"중구청"}'::jsonb, 'pending', 101),
  ('서울', '강남구', '', '강남구', '["https://www.gangnam.go.kr"]'::jsonb, '{"https://www.gangnam.go.kr":"강남구청"}'::jsonb, 'pending', 102),

  ('부산', '해운대구', '', '해운대구', '["https://www.haeundae.go.kr"]'::jsonb, '{"https://www.haeundae.go.kr":"해운대구청"}'::jsonb, 'pending', 110),
  ('대구', '수성구', '', '수성구', '["https://www.suseong.kr"]'::jsonb, '{"https://www.suseong.kr":"수성구청"}'::jsonb, 'pending', 120),
  ('인천', '남동구', '', '남동구', '["https://www.namdong.go.kr"]'::jsonb, '{"https://www.namdong.go.kr":"남동구청"}'::jsonb, 'pending', 130),
  ('광주', '북구', '', '북구', '["https://www.bukgu.gwangju.kr"]'::jsonb, '{"https://www.bukgu.gwangju.kr":"북구청"}'::jsonb, 'pending', 140),
  ('대전', '유성구', '', '유성구', '["https://www.yuseong.go.kr"]'::jsonb, '{"https://www.yuseong.go.kr":"유성구청"}'::jsonb, 'pending', 150),
  ('울산', '남구', '', '남구', '["https://www.ulsannamgu.go.kr"]'::jsonb, '{"https://www.ulsannamgu.go.kr":"남구청"}'::jsonb, 'pending', 160),
  ('세종', '세종시', '', '세종시', '["https://www.sejong.go.kr"]'::jsonb, '{"https://www.sejong.go.kr":"세종시청"}'::jsonb, 'pending', 170),

  ('경기', '고양시', '', '고양시', '["https://www.goyang.go.kr"]'::jsonb, '{"https://www.goyang.go.kr":"고양시청"}'::jsonb, 'pending', 210),
  ('경기', '화성시', '', '화성시', '["https://www.hscity.go.kr"]'::jsonb, '{"https://www.hscity.go.kr":"화성시청"}'::jsonb, 'pending', 211),
  ('경기', '안산시', '', '안산시', '["https://www.ansan.go.kr"]'::jsonb, '{"https://www.ansan.go.kr":"안산시청"}'::jsonb, 'pending', 212),
  ('경기', '안양시', '', '안양시', '["https://www.anyang.go.kr"]'::jsonb, '{"https://www.anyang.go.kr":"안양시청"}'::jsonb, 'pending', 213),
  ('경기', '남양주시', '', '남양주시', '["https://www.nyj.go.kr"]'::jsonb, '{"https://www.nyj.go.kr":"남양주시청"}'::jsonb, 'pending', 214),

  ('강원', '춘천시', '', '춘천시', '["https://www.chuncheon.go.kr"]'::jsonb, '{"https://www.chuncheon.go.kr":"춘천시청"}'::jsonb, 'pending', 310),
  ('강원', '원주시', '', '원주시', '["https://www.wonju.go.kr"]'::jsonb, '{"https://www.wonju.go.kr":"원주시청"}'::jsonb, 'pending', 311),
  ('강원', '강릉시', '', '강릉시', '["https://www.gn.go.kr"]'::jsonb, '{"https://www.gn.go.kr":"강릉시청"}'::jsonb, 'pending', 312),

  ('충북', '충주시', '', '충주시', '["https://www.chungju.go.kr"]'::jsonb, '{"https://www.chungju.go.kr":"충주시청"}'::jsonb, 'pending', 410),
  ('충북', '제천시', '', '제천시', '["https://www.jecheon.go.kr"]'::jsonb, '{"https://www.jecheon.go.kr":"제천시청"}'::jsonb, 'pending', 411),

  ('충남', '천안시', '', '천안시', '["https://www.cheonan.go.kr"]'::jsonb, '{"https://www.cheonan.go.kr":"천안시청"}'::jsonb, 'pending', 510),
  ('충남', '아산시', '', '아산시', '["https://www.asan.go.kr"]'::jsonb, '{"https://www.asan.go.kr":"아산시청"}'::jsonb, 'pending', 511),
  ('충남', '공주시', '', '공주시', '["https://www.gongju.go.kr"]'::jsonb, '{"https://www.gongju.go.kr":"공주시청"}'::jsonb, 'pending', 512),

  ('전북', '군산시', '', '군산시', '["https://www.gunsan.go.kr"]'::jsonb, '{"https://www.gunsan.go.kr":"군산시청"}'::jsonb, 'pending', 610),
  ('전북', '익산시', '', '익산시', '["https://www.iksan.go.kr"]'::jsonb, '{"https://www.iksan.go.kr":"익산시청"}'::jsonb, 'pending', 611),
  ('전북', '정읍시', '', '정읍시', '["https://www.jeongeup.go.kr"]'::jsonb, '{"https://www.jeongeup.go.kr":"정읍시청"}'::jsonb, 'pending', 612),

  ('전남', '순천시', '', '순천시', '["https://www.suncheon.go.kr"]'::jsonb, '{"https://www.suncheon.go.kr":"순천시청"}'::jsonb, 'pending', 710),
  ('전남', '여수시', '', '여수시', '["https://www.yeosu.go.kr"]'::jsonb, '{"https://www.yeosu.go.kr":"여수시청"}'::jsonb, 'pending', 711),
  ('전남', '목포시', '', '목포시', '["https://www.mokpo.go.kr"]'::jsonb, '{"https://www.mokpo.go.kr":"목포시청"}'::jsonb, 'pending', 712),

  ('경북', '포항시', '', '포항시', '["https://www.pohang.go.kr"]'::jsonb, '{"https://www.pohang.go.kr":"포항시청"}'::jsonb, 'pending', 810),
  ('경북', '구미시', '', '구미시', '["https://www.gumi.go.kr"]'::jsonb, '{"https://www.gumi.go.kr":"구미시청"}'::jsonb, 'pending', 811),
  ('경북', '경주시', '', '경주시', '["https://www.gyeongju.go.kr"]'::jsonb, '{"https://www.gyeongju.go.kr":"경주시청"}'::jsonb, 'pending', 812),

  ('경남', '김해시', '', '김해시', '["https://www.gimhae.go.kr"]'::jsonb, '{"https://www.gimhae.go.kr":"김해시청"}'::jsonb, 'pending', 910),
  ('경남', '진주시', '', '진주시', '["https://www.jinju.go.kr"]'::jsonb, '{"https://www.jinju.go.kr":"진주시청"}'::jsonb, 'pending', 911),
  ('경남', '양산시', '', '양산시', '["https://www.yangsan.go.kr"]'::jsonb, '{"https://www.yangsan.go.kr":"양산시청"}'::jsonb, 'pending', 912),

  ('제주', '제주시', '', '제주시', '["https://www.jejusi.go.kr"]'::jsonb, '{"https://www.jejusi.go.kr":"제주시청"}'::jsonb, 'pending', 1010),
  ('제주', '서귀포시', '', '서귀포시', '["https://www.seogwipo.go.kr"]'::jsonb, '{"https://www.seogwipo.go.kr":"서귀포시청"}'::jsonb, 'pending', 1011)
on conflict (region, sub_region, area_detail) do update
set
  source_prefix = excluded.source_prefix,
  seed_urls = excluded.seed_urls,
  seed_titles = excluded.seed_titles,
  priority = excluded.priority,
  status = case
    when public.local_welfare_region_queue.status in ('active', 'paused', 'done')
      then public.local_welfare_region_queue.status
    else excluded.status
  end;

notify pgrst, 'reload schema';
