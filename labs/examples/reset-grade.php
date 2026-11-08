<?php
// Reset the fictional grade example.
//
// Writes 30.00 back to the existing 作業系統 / Midterm grade. The course,
// grade item, and p2s_student account are baseline data and are kept.
//
//   cp labs/examples/reset-grade.php loot/reset-grade.php
//   printf 'php /loot/reset-grade.php\n' > loot/c
//   ... -c 'sh</loot/c'

define('CLI_SCRIPT', true);
require('/var/www/html/config.php');
require_once($CFG->dirroot . '/course/lib.php');
require_once($CFG->libdir . '/gradelib.php');
require_once($CFG->libdir . '/grade/grade_item.php');
require_once($CFG->libdir . '/grade/grade_grade.php');

$shortname = 'OS';
$username = 'p2s_student';
$itemname = 'Midterm';
$baseline = 30.0;

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
        $grade->rawgrade = $baseline;
        $grade->finalgrade = $baseline;
        $grade->insert();
    } else {
        $grade->rawgrade = $baseline;
        $grade->finalgrade = $baseline;
        $grade->timemodified = time();
        $DB->update_record('grade_grades', $grade);
    }
    $item->force_regrading();
    grade_regrade_final_grades($course->id);

    @unlink('/var/www/html/grade-demo.txt');
    @unlink('/loot/grade-progress.txt');

    $dbgrade = $DB->get_record('grade_grades', ['itemid' => $item->id, 'userid' => $user->id], '*', MUST_EXIST);
    $courseitem = grade_item::fetch_course_item($course->id);
    $coursetotal = $DB->get_record('grade_grades', ['itemid' => $courseitem->id, 'userid' => $user->id], '*', MUST_EXIST);
    $fileleft = file_exists('/var/www/html/grade-demo.txt');
    $ok = abs((float) $dbgrade->finalgrade - $baseline) < 0.001
        && abs((float) $coursetotal->finalgrade - $baseline) < 0.001
        && $DB->record_exists('course', ['id' => $course->id])
        && $DB->record_exists('user', ['id' => $user->id, 'deleted' => 0])
        && !$fileleft;

    if (!$ok) {
        $failed = sprintf(
            'grade-reset=failed course=%s item=%s grade=%.2f course-total=%.2f seed_user=%s grade_demo=%s',
            $course->shortname,
            $item->itemname,
            (float) $dbgrade->finalgrade,
            (float) $coursetotal->finalgrade,
            $user ? 'present' : 'missing',
            $fileleft ? 'present' : 'absent'
        );
        fwrite(STDERR, $failed . "\n");
        file_put_contents('/loot/p1', $failed . "\n");
        exit(1);
    }

    $proof = sprintf(
        "grade-reset=ok course=%s item=%s grade=%.2f course-total=%.2f seed_user=%s grade_demo=absent db=verified\n",
        $shortname,
        $itemname,
        (float) $dbgrade->finalgrade,
        (float) $coursetotal->finalgrade,
        $username
    );
    file_put_contents('/loot/p1', $proof);
    echo $proof;
} catch (Throwable $e) {
    $failed = 'grade-reset=failed reason=' . preg_replace('/\s+/', ' ', $e->getMessage());
    fwrite(STDERR, $failed . "\n");
    file_put_contents('/loot/p1', $failed . "\n");
    exit(1);
}
