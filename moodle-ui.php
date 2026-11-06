<?php
// Initialise the local course practice platform.
//
// This script is idempotent. It runs inside the Moodle container after
// installation (and on later starts) and must never overwrite changes a
// student made while practising the lab effects.
//
// The baseline consists of two independent parts:
//   1. Seed data that must exist on every start (the p2s_student account).
//   2. First-run presentation data (site name, banner, categories, language).
//
// Presentation data is applied only while lab_ui_initialized is unset. The
// optional zh_tw language pack is detected at runtime; a download failure
// must not prevent seed data or the rest of the baseline from being applied.

define('CLI_SCRIPT', true);
require('/var/www/html/config.php');
require_once($CFG->dirroot . '/course/lib.php');
require_once($CFG->dirroot . '/user/lib.php');
require_once($CFG->libdir . '/enrollib.php');
require_once($CFG->libdir . '/gradelib.php');
require_once($CFG->libdir . '/grade/grade_item.php');
require_once($CFG->libdir . '/grade/grade_grade.php');

$haslang = is_dir($CFG->dataroot . '/lang/zh_tw');
$initialized = (bool) get_config('core', 'lab_ui_initialized');

try {
    if (!$initialized) {
        // Presentation baseline. These fields are only set once, so a student
        // who renames the front page keeps that change across restarts.
        set_config('theme', 'boost');
        set_config('frontpage', '2');
        set_config('frontpageloggedin', '2');
        set_config('sitenameintitle', 'fullname');
        set_config('additionalhtmltopofbody', '<div style="background:linear-gradient(110deg,#1f4e79 0%,#3f7fa6 58%,#7aa8bd 100%);color:#fff;margin-top:60px;padding:24px 40px;"><div style="font-size:30px;font-weight:700;letter-spacing:0.02em;">成功大學資訊安全學習平臺</div><div style="font-size:16px;margin-top:6px;opacity:0.92;">這不是真的成大的 Moodle</div></div>');
        set_config('brandcolor', '#1f4e79', 'theme_boost');
        set_config('additionalhtmlfooter', '<div style="text-align:center;color:#5f6b76;font-size:13px;padding:10px 16px;">這不是成大的正式 Moodle；所有資料均為虛構測試資料。</div>');

        $summary = <<<'HTML'
<div style="background:linear-gradient(110deg,#1f4e79 0%,#3f7fa6 58%,#7aa8bd 100%);color:#fff;padding:28px 32px;border-radius:4px;margin-bottom:18px;">
  <div style="font-size:30px;font-weight:700;letter-spacing:0.02em;">成功大學資訊安全學習平臺</div>
  <div style="font-size:16px;margin-top:8px;opacity:0.92;">這不是成大的正式 Moodle</div>
</div>
<p><strong>練習平台說明：</strong>這不是成大的正式 Moodle。課程、帳號與成績均為虛構測試資料。</p>
HTML;

        $site = $DB->get_record('course', ['id' => 1], '*', MUST_EXIST);
        $site->fullname = 'NCKU Moodle';
        $site->shortname = 'NCKU Moodle';
        $site->summary = $summary;
        $site->summaryformat = FORMAT_HTML;
        $DB->update_record('course', $site);

        if ($defaultcat = $DB->get_record('course_categories', ['id' => 1])) {
            if ($defaultcat->name === 'Category 1') {
                $DB->set_field('course_categories', 'name', '課程類別', ['id' => 1]);
            }
        }
    }

    // Categories are part of the baseline. Ensure they exist on every start,
    // but never rename a category the student already created or changed.
    foreach (['資訊安全', '作業系統', '測試課程'] as $name) {
        if (!$DB->record_exists('course_categories', ['name' => $name])) {
            \core_course_category::create([
                'name' => $name,
                'parent' => 0,
                'visible' => 1,
                'description' => '課程練習平台的分類。',
            ]);
        }
    }

    // Language is optional. If the pack is unavailable, keep the current
    // language and finish the rest of the baseline. When the pack appears on a
    // later start, apply the language once without touching presentation data.
    if ($haslang && !get_config('core', 'lab_lang_initialized')) {
        set_config('lang', 'zh_tw');
        set_config('autolang', '0');
        set_config('langmenu', '0');
        set_config('lab_lang_initialized', 1);
    } elseif (!$haslang) {
        echo "zh_tw language pack is missing; continuing without changing language.\n";
    }

    // Seed data. This account belongs to the baseline, so it is checked on
    // every start. Existing accounts (including a changed password) are kept.
    $seed = $DB->get_record('user', ['username' => 'p2s_student']);
    if (!$seed) {
        $seed = (object) [
            'username' => 'p2s_student',
            'password' => 'StudentOnly-2026',
            'firstname' => 'P2S',
            'lastname' => 'Student',
            'email' => 'p2s.student@example.invalid',
            'auth' => 'manual',
            'confirmed' => 1,
            'mnethostid' => $CFG->mnet_localhost_id,
        ];
        user_create_user($seed, true, false);
        echo "Created seed account p2s_student.\n";
    } elseif ($seed->deleted) {
        $DB->set_field('user', 'deleted', 0, ['id' => $seed->id]);
        echo "Restored seed account p2s_student.\n";
    }

    // Grade baseline: "作業系統" with one "Midterm" item at 30.00.
    // This runs on every start so missing pieces are restored, but an existing
    // grade is never overwritten. A 100 produced by the demo stays at 100 until
    // the instructor explicitly resets it to 30.
    $course = $DB->get_record('course', ['shortname' => 'OS']);
    if (!$course) {
        $cat = $DB->get_record('course_categories', ['name' => '作業系統']);
        $course = create_course((object) [
            'fullname' => '作業系統',
            'shortname' => 'OS',
            'category' => $cat ? $cat->id : 1,
            'format' => 'topics',
            'visible' => 1,
            'summary' => 'Fictional operating systems course used by the PHP2Shell Lab.',
        ]);
        echo "Created baseline course 作業系統 (OS).\n";
    }

    $student = $DB->get_record('user', ['username' => 'p2s_student', 'deleted' => 0], '*', MUST_EXIST);
    $enrol = enrol_get_plugin('manual');
    $instance = $DB->get_record('enrol', ['courseid' => $course->id, 'enrol' => 'manual']);
    if (!$instance) {
        $enrol->add_instance($course);
        $instance = $DB->get_record('enrol', ['courseid' => $course->id, 'enrol' => 'manual'], '*', MUST_EXIST);
    }
    $roleid = $DB->get_field('role', 'id', ['shortname' => 'student'], MUST_EXIST);
    if (!$DB->record_exists('user_enrolments', ['enrolid' => $instance->id, 'userid' => $student->id])) {
        $enrol->enrol_user($instance, $student->id, $roleid);
    }

    $item = $DB->get_record('grade_items', [
        'courseid' => $course->id,
        'itemtype' => 'manual',
        'itemname' => 'Midterm',
    ]);
    if (!$item) {
        $item = new grade_item();
        $item->courseid = $course->id;
        $item->itemtype = 'manual';
        $item->itemname = 'Midterm';
        $item->itemnumber = 1;
        $item->gradetype = GRADE_TYPE_VALUE;
        $item->grademax = 100;
        $item->grademin = 0;
        $item->insert();
        echo "Created baseline grade item Midterm.\n";
    }

    $grade = $DB->get_record('grade_grades', ['itemid' => $item->id, 'userid' => $student->id]);
    if (!$grade) {
        $grade = new grade_grade();
        $grade->itemid = $item->id;
        $grade->userid = $student->id;
        $grade->rawgrade = 30;
        $grade->finalgrade = 30;
        $grade->insert();
        grade_regrade_final_grades($course->id);
        echo "Created baseline Midterm grade 30.00.\n";
    }

    // Set the marker only after every required baseline item exists. If the
    // script fails early, the next start retries instead of reporting success.
    if (!$initialized) {
        set_config('lab_ui_initialized', 1);
    }

    purge_caches();

    $checkuser = $DB->get_record('user', ['username' => 'p2s_student', 'deleted' => 0]);
    if (!$checkuser) {
        fwrite(STDERR, "Baseline verification failed: p2s_student is missing.\n");
        exit(1);
    }
    if (!get_config('core', 'lab_ui_initialized')) {
        fwrite(STDERR, "Baseline verification failed: lab_ui_initialized is not set.\n");
        exit(1);
    }

    $basecourse = $DB->get_record('course', ['shortname' => 'OS'], '*', MUST_EXIST);
    $baseitem = $DB->get_record('grade_items', ['courseid' => $basecourse->id, 'itemname' => 'Midterm'], '*', MUST_EXIST);
    $basegrade = $DB->get_record('grade_grades', ['itemid' => $baseitem->id, 'userid' => $checkuser->id], '*', MUST_EXIST);
    $langstate = $haslang ? 'zh_tw' : 'unavailable';
    echo "Moodle baseline ready (site=NCKU Moodle, user=p2s_student, course=作業系統, midterm=" . (float) $basegrade->finalgrade . ", lang={$langstate}).\n";
} catch (Throwable $e) {
    fwrite(STDERR, 'Moodle baseline failed: ' . $e->getMessage() . "\n");
    exit(1);
}
