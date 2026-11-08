import json
import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
import soundfile as sf

from engine import Hrtf, RATE, ambience, automation, load_audio, render, spatialize


class AudioEngineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.hrtf=Hrtf()

    def test_keyframe_interpolation_and_holds(self):
        obj=dict(y=2,keyframes=[dict(time=0,y=6),dict(time=10,y=1)],interpolation='linear')
        np.testing.assert_allclose(automation(obj,np.array([-2,0,5,10,12]),'y'),[6,6,3.5,1,1])
        obj['interpolation']='step'
        self.assertEqual(float(automation(obj,5,'y')),6)

    def test_right_and_left_ear_direction(self):
        impulse=np.zeros((RATE//3,1),np.float32);impulse[400]=.5
        right=spatialize(impulse,dict(x=3,y=0,z=0,gain=0),self.hrtf,{},0)
        left=spatialize(impulse,dict(x=-3,y=0,z=0,gain=0),self.hrtf,{},0)
        self.assertGreater(float(np.sum(right[:,1]**2)),float(np.sum(right[:,0]**2)))
        self.assertGreater(float(np.sum(left[:,0]**2)),float(np.sum(left[:,1]**2)))

    def test_source_length_and_peak_protection_and_formats(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'input.wav'
            t=np.arange(RATE)/RATE
            sf.write(path,np.sin(t*2*np.pi*440)*.7,RATE,subtype='FLOAT')
            obj=dict(path=str(path),name='test',x=-2,y=1,z=.4,gain=16,reverb=.25,echo=.2,distortion=.15,decay=.6)
            project=dict(duration=1,tail=.5,objects=[obj],masterGain=0,protectPeaks=True)
            for fmt,ext in [('wav24','wav'),('wav32','wav'),('flac','flac'),('aiff','aiff'),('caf','caf'),('w64','w64'),('mp3','mp3'),('aac','m4a'),('alac','m4a'),('opus','opus'),('vorbis','ogg')]:
                result=render(project|dict(format=fmt),str(Path(tmp)/f'{fmt}.{ext}'))
                self.assertTrue(Path(result['path']).is_file())
                self.assertEqual(result['sampleRate'],48000)
                self.assertEqual(result['channels'],2)
                self.assertLessEqual(result['peakDb'],-1.19)
                self.assertAlmostEqual(result['duration'],1.5,places=3)
                decoded=load_audio(result['path'])
                self.assertEqual(decoded.shape[1],2)
                self.assertTrue(np.isfinite(decoded).all())

    def test_solo_mute_render_silence(self):
        with tempfile.TemporaryDirectory() as tmp:
            file=str(Path(tmp)/'silence.wav')
            render(dict(duration=.1,tail=0,objects=[dict(generator='rain',mute=True)]),file)
            audio,_=sf.read(file)
            self.assertEqual(float(np.max(abs(audio))),0)

    def test_bezier_motion_changes_the_rendered_audio(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=Path(tmp)/'tone.wav'
            sf.write(source,np.sin(np.arange(RATE//3)*2*np.pi*330/RATE)*.25,RATE)
            obj=dict(path=str(source),x=-3,y=1,gain=0,reverb=0,highpass=40,lowpass=18000,interpolation='linear',keyframes=[{'time':0,'x':-3,'x.outT':.08,'x.outV':3},{'time':.3,'x':3,'x.inT':.24,'x.inV':-3}])
            project=dict(duration=.3,tail=0,objects=[obj])
            first=Path(tmp)/'linear.wav';second=Path(tmp)/'curve.wav'
            render(project,str(first))
            obj['interpolationByField']={'x':'bezier'}
            render(project,str(second))
            a,_=sf.read(first);b,_=sf.read(second)
            self.assertGreater(float(np.max(abs(a-b))),.001)

    def test_ambience_finite_and_reproducible(self):
        for kind in ['rain','wind','ocean','white','pink']:
            a=ambience(kind,.1)
            self.assertEqual(a.shape,(4800,2))
            self.assertTrue(np.isfinite(a).all())
            np.testing.assert_array_equal(a,ambience(kind,.1))

    def test_worker_doctor_and_invalid_task(self):
        worker=Path(__file__).with_name('worker.py')
        result=subprocess.run([sys.executable,str(worker)],input='{"action":"doctor"}\n',capture_output=True,text=True,encoding='utf-8')
        event=json.loads(result.stdout.strip())
        self.assertEqual(event['event'],'result')
        self.assertTrue(event['data']['hrtf'])
        result=subprocess.run([sys.executable,str(worker)],input='{"action":"bad"}\n',capture_output=True,text=True,encoding='utf-8')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(json.loads(result.stdout.strip())['event'],'error')

    def test_bezier_handles_channel_modes_and_dense_audio_automation(self):
        obj=dict(interpolation='linear',interpolationByField={'y':'bezier'},keyframes=[{'time':0,'y':0,'y.outT':2,'y.outV':8},{'time':10,'y':10,'y.inT':8,'y.inV':2}])
        self.assertAlmostEqual(float(automation(obj,5,'y')),5,places=7)
        dense_times=np.linspace(-1,11,20000)
        dense=automation(obj,dense_times,'y')
        self.assertTrue(np.isfinite(dense).all())
        self.assertEqual(dense[0],0)
        self.assertEqual(dense[-1],10)
        sample=np.array([.4,1.3,2.7,6.1,8.8])
        exact=automation(obj,sample,'y')
        np.testing.assert_allclose(np.interp(sample,dense_times,dense),exact,atol=2e-5)
        obj['interpolationByField']['y']='step'
        self.assertEqual(float(automation(obj,5,'y')),0)


if __name__=='__main__':unittest.main(verbosity=2)
