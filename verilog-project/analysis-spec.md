<!-- 작성 안내 (유저용. 분석 내용이 아니므로 Claude는 이 주석을 무시한다)
- 아래 분석 스펙을 사용할 경우 주석을 지우고 작성한다.
- 이 주석은 지워도 되고 남겨 둬도 된다.
-->

# 분석 스펙

## Top
<!--
- top 은 sauvage
-->

## 입력 & 파라미터 조건
<!--
- start 는 1클럭 pulse 이고, 연속 2클럭 이상 1이 되지 않는다
- start 는 이전 작업의 done 이 나온 뒤에만 다시 온다
- s_axis (tvalid / tready / tdata[63:0] / tkeep[7:0] / tlast) 는 AXI4-Stream 규칙을 지킨다. tvalid 가 1이 되면 tready 를 받을 때까지 값을 유지한다
-->

## 출력 조건
<!--
- m_axis (tvalid / tready / tdata[63:0] / tlast) 는 AXI4-Stream 규칙을 지켜야 한다
- 받는 쪽은 m_axis_tready 를 최대 16클럭까지 0 으로 둘 수 있다
- done 은 마지막 출력 beat 가 나간 다음 클럭에 1클럭 pulse 로 낸다
-->

## 의도된 동작
<!--
- srst 가 오면 처리 중이던 프레임은 버린다 (남은 출력 beat 를 내지 않는다)
-->

## 성능 목표
<!--
- 처리율: 입력 1 beat 당 1클럭 (back-to-back 입력을 멈추지 않고 처리)
-->

## 전력 목표
<!--
- 합성 도구가 enable 에서 클럭 게이팅을 자동으로 넣는다
-->

## 요청 사항
<!--
- 마지막 beat 의 tkeep 이 부분 유효 (예: 8'h0F) 일 때 출력 데이터 바이트 정렬이 맞는지 확인
- m_axis_tready 가 오래 0 일 때 입력 데이터가 유실되거나 중복되는지 확인
- 작업 중 srst 가 오면 다음 start 부터 정상 동작하는지 확인
-->
