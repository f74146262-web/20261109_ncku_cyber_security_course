<?php
// Student example: set the baseline "作業系統 / Midterm" grade to 100.
//
// The course, student, and grade item are created by the Moodle baseline.
// This script only changes the existing grade. Reset with reset-grade.php,
// which writes 30.00 back; it does not delete the course or the student.
//
//   cp labs/examples/grade.php loot/grade.php
//   printf 'php /loot/grade.php 100\n' > loot/c
//   ... -c 'sh</loot/c'
//
// Progress and final evidence are separate:
//   /loot/grade-progress.txt  - stage markers (started, item-ready, ...)
//   /loot/p1                  - written only after the DB read-back matches.

define('CLI_SCRIPT', true);
require('/var/www/html/config.php');
require_once($CFG->dirroot . '/course/lib.php');
require_once($CFG->dirroot . '/user/lib.php');
require_once($CFG->libdir . '/gradelib.php');
require_once($CFG->libdir . '/grade/grade_item.php');
require_once($CFG->libdir . '/grade/grade_grade.php');

$shortname = 'OS';
$username = 'p2s_student';
$itemname = 'Midterm';
$gradevalue = isset($argv[1]) ? (float) $argv[1] : 100.0;
$gradevalue = max(0.0, min(100.0, $gradevalue));

$progressfile = '/loot/grade-progress.txt';
$stage = function (string $stage, array $fields = []) use ($progressfile): void {
    $parts = ["stage={$stage}"];
    foreach ($fields as $key => $value) {
        $parts[] = "{$key}={$value}";
    }
    file_put_contents($progressfile, implode(' ', $parts) . "\n", FILE_APPEND);
};

file_put_contents($progressfile, '');
$stage('started', ['score' => $gradevalue]);

try {
    $course = $DB->get_record('course', ['shortname' => $shortname], '*', MUST_EXIST);
    $user = $DB->get_record('user', ['username' => $username, 'deleted' => 0], '*', MUST_EXIST);
    $item = grade_item::fetch([
        'courseid' => $course->id,
        'itemtype' => 'manual',
        'itemname' => $itemname,
    ]);
    if (!$item) {
        throw new RuntimeException('Midterm grade item not found');
    }
    $grade = $DB->get_record('grade_grades', ['itemid' => $item->id, 'userid' => $user->id]);
    if (!$grade) {
        $grade = new grade_grade();
        $grade->itemid = $item->id;
        $grade->userid = $user->id;
        $grade->rawgrade = $gradevalue;
        $grade->finalgrade = $gradevalue;
        $grade->insert();
    } else {
        $grade->rawgrade = $gradevalue;
        $grade->finalgrade = $gradevalue;
        $grade->timemodified = time();
        $DB->update_record('grade_grades', $grade);
    }
    $item->force_regrading();
    grade_regrade_final_grades($course->id);
    $stage('grade-written', ['itemid' => $item->id]);

    $dbcourse = $DB->get_record('course', ['id' => $course->id], '*', MUST_EXIST);
    $dbuser = $DB->get_record('user', ['id' => $user->id, 'deleted' => 0], '*', MUST_EXIST);
    $dbitem = $DB->get_record('grade_items', ['id' => $item->id], '*', MUST_EXIST);
    $dbgrade = $DB->get_record('grade_grades', ['itemid' => $item->id, 'userid' => $user->id], '*', MUST_EXIST);
    $courseitem = grade_item::fetch_course_item($course->id);
    $coursetotal = $DB->get_record('grade_grades', ['itemid' => $courseitem->id, 'userid' => $user->id], '*', MUST_EXIST);
    $actual = (float) $dbgrade->finalgrade;
    $actualtotal = (float) $coursetotal->finalgrade;
    $ok = $dbcourse->shortname === $shortname
        && $dbuser->username === $username
        && $dbitem->itemname === $itemname
        && (float) $dbitem->grademax === 100.0
        && abs($actual - $gradevalue) < 0.001
        && abs($actualtotal - $gradevalue) < 0.001;

    if (!$ok) {
        throw new RuntimeException(sprintf(
            'expected grade and course total %.2f, read back %.2f and %.2f',
            $gradevalue, $actual, $actualtotal
        ));
    }

    $proof = sprintf(
        "grade-state=complete grade=%.2f finalgrade=%.2f course-total=%.2f student=%s course=%s courseid=%d userid=%d itemid=%d db=verified\n",
        $gradevalue,
        $actual,
        $actualtotal,
        $username,
        $shortname,
        $course->id,
        $user->id,
        $item->id
    );
    file_put_contents($progressfile, $proof, FILE_APPEND);
    file_put_contents('/loot/p1', $proof);
    file_put_contents('/var/www/html/grade-demo.txt', $proof);
    echo $proof;
} catch (Throwable $e) {
    $failed = 'grade-state=failed reason=' . preg_replace('/\s+/', ' ', $e->getMessage());
    file_put_contents($progressfile, $failed . "\n", FILE_APPEND);
    fwrite(STDERR, $failed . "\n");
    exit(1);
}
