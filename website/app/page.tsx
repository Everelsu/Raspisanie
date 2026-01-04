import HomeClient from './HomeClient';

// Это *серверная* страница-обертка.
// Мы явно запрещаем статическую генерацию и ISR, чтобы Next не пытался пререндерить "/".
export const dynamic = 'force-dynamic';
export const revalidate = false;

export default function Page() {
  return <HomeClient />;
}

